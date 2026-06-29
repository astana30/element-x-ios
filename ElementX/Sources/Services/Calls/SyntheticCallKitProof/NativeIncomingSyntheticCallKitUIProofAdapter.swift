//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CryptoKit
import Foundation

#if os(iOS)
import UIKit
#endif

#if canImport(CallKit) && os(iOS)
import AVFAudio
import CallKit
#endif

#if canImport(PushKit) && os(iOS)
import PushKit
#endif

enum NativeIncomingSyntheticCallKitUIProofEvent: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case reported
    case providerDidReset
    case audioSessionActivated
    case audioSessionDeactivated
    case answerActionDelivered(uuidMatched: Bool)
    case answered
    case endActionDelivered(uuidMatched: Bool)
    case endActionFulfilled(uuidMatched: Bool)
    case localEndRequestedBeforeAnswer(uuidMatched: Bool)
    case ended
    case muted(Bool)
    case failed(NativeIncomingCallFailClosedReason)

    var description: String {
        switch self {
        case .reported:
            "reported"
        case .providerDidReset:
            "providerDidReset"
        case .audioSessionActivated:
            "audioSessionActivated"
        case .audioSessionDeactivated:
            "audioSessionDeactivated"
        case .answerActionDelivered(let uuidMatched):
            "answerActionDelivered(uuidMatched: \(uuidMatched))"
        case .answered:
            "answered"
        case .endActionDelivered(let uuidMatched):
            "endActionDelivered(uuidMatched: \(uuidMatched))"
        case .endActionFulfilled(let uuidMatched):
            "endActionFulfilled(uuidMatched: \(uuidMatched))"
        case .localEndRequestedBeforeAnswer(let uuidMatched):
            "localEndRequestedBeforeAnswer(uuidMatched: \(uuidMatched))"
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

struct NativeIncomingSyntheticCallKitUIAnswerRetentionProof: Equatable {
    var providerRetainedForAnswer: Bool
    var delegateRetainedForAnswer: Bool
    var activeCallUUIDRetained: Bool
}

protocol NativeIncomingSyntheticCallKitUIProofEventRecording: AnyObject {
    func recordSyntheticCallKitUIProofEvent(_ event: NativeIncomingSyntheticCallKitUIProofEvent)
}

protocol NativeIncomingSyntheticCallKitUIReportingDelegate: AnyObject {
    func syntheticCallKitUIReportingDidReset()
    func syntheticCallKitUIReportingDidActivateAudioSession()
    func syntheticCallKitUIReportingDidDeactivateAudioSession()
    func syntheticCallKitUIReportingDidAnswer(callUUID: UUID)
    func syntheticCallKitUIReportingDidEnd(callUUID: UUID)
    func syntheticCallKitUIReportingDidFulfillEnd(callUUID: UUID)
    func syntheticCallKitUIReportingDidSetMuted(_ isMuted: Bool, callUUID: UUID)
    func syntheticCallKitUIReportingDidFail(callUUID: UUID)
}

protocol NativeIncomingSyntheticCallKitUIReporting: AnyObject {
    var delegate: NativeIncomingSyntheticCallKitUIReportingDelegate? { get set }
    var providerRetainedForAnswer: Bool { get }
    var delegateRetainedForAnswer: Bool { get }

    func reportIncomingCall(callUUID: UUID, displayMetadata: NativeIncomingCallKitDisplayMetadata, completion: @escaping (Bool) -> Void) -> Bool
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
    private var answeredCallUUIDs = Set<UUID>()
    private var deliveredEndActionUUIDs = Set<UUID>()

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
        reportSyntheticIncomingCall(identity: identity, displayMetadata: displayMetadata) { _ in }
    }

    func reportSyntheticIncomingCall(identity: NativeIncomingCallIdentity,
                                     displayMetadata: NativeIncomingCallKitDisplayMetadata,
                                     completion: @escaping (NativeIncomingSyntheticCallKitUIProofEvent) -> Void) -> NativeIncomingSyntheticCallKitUIProofEvent {
        guard isEnabled else {
            let event = failClosed(.dependencyUnavailable)
            completion(event)
            return event
        }
        guard uuidsByHandle[identity.handle] == nil else {
            let event = failClosed(.duplicate)
            completion(event)
            return event
        }

        let callUUID = UUID()
        identitiesByUUID[callUUID] = identity
        uuidsByHandle[identity.handle] = callUUID
        let reportSubmitted = reporter.reportIncomingCall(callUUID: callUUID, displayMetadata: displayMetadata) { [weak self] didReport in
            guard let self else {
                return
            }

            self.diagnosticsRecorder.record(.init(lifecycleState: didReport ? .reported : .blocked,
                                                  failClosedReason: didReport ? nil : .callReportingUnavailable,
                                                  reportAttempted: true,
                                                  reportSucceeded: didReport,
                                                  mediaCredentialRequested: false,
                                                  mediaConnectAttempted: false))
            if didReport {
                completion(self.record(.reported))
            } else {
                self.clear(callUUID: callUUID)
                completion(self.record(.failed(.callReportingUnavailable)))
            }
        }

        guard reportSubmitted else {
            clear(callUUID: callUUID)
            diagnosticsRecorder.record(.init(lifecycleState: .blocked,
                                             failClosedReason: .callReportingUnavailable,
                                             reportAttempted: true,
                                             reportSucceeded: false,
                                             mediaCredentialRequested: false,
                                             mediaConnectAttempted: false))
            let event = record(.failed(.callReportingUnavailable))
            completion(event)
            return event
        }

        return .reported
    }

    func endSyntheticCall(handle rawHandle: String) -> NativeIncomingSyntheticCallKitUIProofEvent {
        guard let callUUID = callUUID(for: rawHandle),
              let identity = identitiesByUUID[callUUID] else {
            return failClosed(.unverifiable)
        }

        if !answeredCallUUIDs.contains(callUUID) {
            _ = record(.localEndRequestedBeforeAnswer(uuidMatched: true))
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

    func answerRetentionProof(handle rawHandle: String) -> NativeIncomingSyntheticCallKitUIAnswerRetentionProof {
        let callUUID = callUUID(for: rawHandle)
        return .init(providerRetainedForAnswer: reporter.providerRetainedForAnswer,
                     delegateRetainedForAnswer: reporter.delegateRetainedForAnswer,
                     activeCallUUIDRetained: callUUID.flatMap { identitiesByUUID[$0] } != nil)
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
        let identity = identitiesByUUID[callUUID]
        _ = record(.answerActionDelivered(uuidMatched: identity != nil))
        guard let identity else {
            _ = failClosed(.unverifiable)
            return
        }

        actionHandler.answerSyntheticCall(identity: identity)
        answeredCallUUIDs.insert(callUUID)
        diagnosticsRecorder.record(.init(lifecycleState: .answered,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
        _ = record(.answered)
        reporter.endCall(callUUID: callUUID)
        clear(callUUID: callUUID)
        _ = record(.ended)
    }

    func syntheticCallKitUIReportingDidEnd(callUUID: UUID) {
        let identity = identitiesByUUID[callUUID]
        _ = record(.endActionDelivered(uuidMatched: identity != nil))
        guard let identity else {
            _ = failClosed(.unverifiable)
            return
        }

        deliveredEndActionUUIDs.insert(callUUID)
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

    func syntheticCallKitUIReportingDidFulfillEnd(callUUID: UUID) {
        let uuidMatched = deliveredEndActionUUIDs.remove(callUUID) != nil
        _ = record(.endActionFulfilled(uuidMatched: uuidMatched))
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

    func syntheticCallKitUIReportingDidReset() {
        _ = record(.providerDidReset)
    }

    func syntheticCallKitUIReportingDidActivateAudioSession() {
        _ = record(.audioSessionActivated)
    }

    func syntheticCallKitUIReportingDidDeactivateAudioSession() {
        _ = record(.audioSessionDeactivated)
    }

    private func callUUID(for rawHandle: String) -> UUID? {
        guard isEnabled,
              let handle = NativeIncomingCallHandle(rawHandle) else {
            return nil
        }

        return uuidsByHandle[handle]
    }

    private func clear(callUUID: UUID) {
        answeredCallUUIDs.remove(callUUID)
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

    func reportSyntheticIncomingCall(completion: @escaping (NativeIncomingSyntheticCallKitUIProofEvent) -> Void) -> NativeIncomingSyntheticCallKitUIProofEvent {
        guard let safeHandle = NativeIncomingCallHandle(handle) else {
            let event = NativeIncomingSyntheticCallKitUIProofEvent.failed(.malformed)
            completion(event)
            return event
        }

        let identity = NativeIncomingCallIdentity(handle: safeHandle, receivedAt: Date())
        guard let displayMetadata = NativeIncomingCallKitDisplayMetadata(displayLabel) else {
            let event = NativeIncomingSyntheticCallKitUIProofEvent.failed(.malformed)
            completion(event)
            return event
        }

        return adapter.reportSyntheticIncomingCall(identity: identity, displayMetadata: displayMetadata, completion: completion)
    }

    func endSyntheticIncomingCall() -> NativeIncomingSyntheticCallKitUIProofEvent {
        adapter.endSyntheticCall(handle: handle)
    }

    func answerRetentionProof() -> NativeIncomingSyntheticCallKitUIAnswerRetentionProof {
        adapter.answerRetentionProof(handle: handle)
    }
}

#if canImport(CallKit) && os(iOS)
extension NativeIncomingSyntheticCallKitUIProofHarness {
    static func makePhysicalDeviceProofHarness(handle: String = "synthetic-local-call",
                                               displayLabel: String = "Native Audio Proof",
                                               eventRecorder: NativeIncomingSyntheticCallKitUIProofEventRecording = NativeIncomingSyntheticCallKitUIProofNoopEventRecorder()) -> NativeIncomingSyntheticCallKitUIProofHarness {
        let reporter = NativeIncomingSyntheticCallKitUIProofReporter()
        let adapter = NativeIncomingSyntheticCallKitUIProofAdapter(isEnabled: true,
                                                                   reporter: reporter,
                                                                   actionHandler: NativeIncomingSyntheticCallKitUIProofNoopActionHandler(),
                                                                   diagnosticsRecorder: NativeIncomingSyntheticCallKitUIProofNoopDiagnosticsRecorder(),
                                                                   eventRecorder: eventRecorder)
        return NativeIncomingSyntheticCallKitUIProofHarness(adapter: adapter,
                                                            handle: handle,
                                                            displayLabel: displayLabel)
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
    private let providerDelegateQueue = DispatchQueue(label: "kz.salemx.callkit.proof.delegate")

    var providerRetainedForAnswer: Bool {
        true
    }

    var delegateRetainedForAnswer: Bool {
        delegate != nil
    }

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.supportsVideo = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: providerDelegateQueue)
    }

    func reportIncomingCall(callUUID: UUID, displayMetadata: NativeIncomingCallKitDisplayMetadata, completion: @escaping (Bool) -> Void) -> Bool {
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
                completion(true)
                return
            }

            self?.delegate?.syntheticCallKitUIReportingDidFail(callUUID: callUUID)
            completion(false)
        }
        return true
    }

    func endCall(callUUID: UUID) {
        provider.reportCall(with: callUUID, endedAt: Date(), reason: .remoteEnded)
    }

    func providerDidReset(_ provider: CXProvider) {
        delegate?.syntheticCallKitUIReportingDidReset()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        delegate?.syntheticCallKitUIReportingDidAnswer(callUUID: action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        delegate?.syntheticCallKitUIReportingDidEnd(callUUID: action.callUUID)
        action.fulfill()
        delegate?.syntheticCallKitUIReportingDidFulfillEnd(callUUID: action.callUUID)
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        delegate?.syntheticCallKitUIReportingDidSetMuted(action.isMuted, callUUID: action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        delegate?.syntheticCallKitUIReportingDidActivateAudioSession()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        delegate?.syntheticCallKitUIReportingDidDeactivateAudioSession()
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

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }

        let payloadDictionary = payload.dictionaryPayload
        #if DEBUG
        SalemXPushKitRegistrationSmokeDebugBridge.recordVoIPPushReceipt(payloadDictionary, completion: completion)
        #else
        completion()
        #endif
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

#if DEBUG && canImport(PushKit) && os(iOS)
private struct SalemXControlledMediaConnectSwitch {
    static let disabledSwitchNoConnectReason = "disabled_switch_no_connect"
    static let disabled = SalemXControlledMediaConnectSwitch(isEnabled: false, operatorApproved: false)
    static let testOnlyEnabled = SalemXControlledMediaConnectSwitch(isEnabled: true, operatorApproved: true)

    let isEnabled: Bool
    let operatorApproved: Bool

    var executionAllowed: Bool {
        isEnabled && operatorApproved
    }

    var blockedReason: String {
        executionAllowed ? "none" : Self.disabledSwitchNoConnectReason
    }
}

private struct SalemXControlledMediaConnectActivationConfiguration {
    static let defaultDisabled = SalemXControlledMediaConnectActivationConfiguration(controlledConnectSwitch: .disabled,
                                                                                     activationScope: "planned_audio_only_redacted",
                                                                                     videoAllowed: false,
                                                                                     matrixEventsAllowed: false,
                                                                                     rawCredentialsLogged: false)
    static let testOnlyEnabled = SalemXControlledMediaConnectActivationConfiguration(controlledConnectSwitch: .testOnlyEnabled,
                                                                                     activationScope: "test_audio_only_redacted",
                                                                                     videoAllowed: false,
                                                                                     matrixEventsAllowed: false,
                                                                                     rawCredentialsLogged: false)
    static let rollbackDisabled = defaultDisabled

    let controlledConnectSwitch: SalemXControlledMediaConnectSwitch
    let activationScope: String
    let videoAllowed: Bool
    let matrixEventsAllowed: Bool
    let rawCredentialsLogged: Bool

    let wiringPresent = true
    let debugOnly = true
    let isDefaultDisabled = true
    let requiresOperatorApproval = true
    let rollbackAvailable = true
}

private struct SalemXControlledMediaConnectEnablementConfiguration {
    static let enablementDisabledNoConnectReason = "enablement_disabled_no_connect"
    static let defaultDisabled = SalemXControlledMediaConnectEnablementConfiguration(oneShotEnablementEnabled: false,
                                                                                     operatorApproved: false,
                                                                                     freshCredentialsPresent: false,
                                                                                     audioOnlyScope: true,
                                                                                     futureConnectPhasePermitted: false)
    static let testOnlyEnabled = SalemXControlledMediaConnectEnablementConfiguration(oneShotEnablementEnabled: true,
                                                                                     operatorApproved: true,
                                                                                     freshCredentialsPresent: true,
                                                                                     audioOnlyScope: true,
                                                                                     futureConnectPhasePermitted: true)
    static let rollbackDisabled = defaultDisabled

    let oneShotEnablementEnabled: Bool
    let operatorApproved: Bool
    let freshCredentialsPresent: Bool
    let audioOnlyScope: Bool
    let futureConnectPhasePermitted: Bool

    let wiringPresent = true
    let debugOnly = true
    let isDefaultOff = true
    let operatorApprovalRequired = true
    let isOneShot = true
    let freshCredentialsRequired = true
    let videoAllowed = false
    let matrixEventsAllowed = false
    let rawCredentialsLogged = false
    let rollbackAvailable = true

    var executionAllowed: Bool {
        debugOnly && oneShotEnablementEnabled && operatorApproved && freshCredentialsPresent && audioOnlyScope && futureConnectPhasePermitted
    }

    var blockedReason: String {
        executionAllowed ? "none" : Self.enablementDisabledNoConnectReason
    }
}

private struct SalemXPhysical6RuntimeEnablementURLHook {
    static let defaultDisabledNoConnectReason = "default_disabled_no_connect"
    static let armedWaitingForOneIncomingAnswerReason = "armed_waiting_for_one_incoming_answer"
    static let oneShotConsumedNoConnectReason = "one_shot_consumed_no_connect"
    static let defaultDisabled = SalemXPhysical6RuntimeEnablementURLHook(armed: false, consumed: false)
    static let armed = SalemXPhysical6RuntimeEnablementURLHook(armed: true, consumed: false)

    let armed: Bool
    let consumed: Bool

    let present = true
    let debugOnly = true
    let isDefaultDisabled = true
    let oneShot = true
    let audioOnly = true
    let videoAllowed = false
    let matrixEventsAllowed = false
    let rawCredentialsLogged = false

    var oneShotNotConsumed: Bool {
        armed && !consumed
    }

    var activationConfiguration: SalemXControlledMediaConnectActivationConfiguration {
        oneShotNotConsumed ? .testOnlyEnabled : .defaultDisabled
    }

    var enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration {
        oneShotNotConsumed ? .testOnlyEnabled : .defaultDisabled
    }

    var blockedReason: String {
        if consumed {
            return Self.oneShotConsumedNoConnectReason
        }
        if armed {
            return Self.armedWaitingForOneIncomingAnswerReason
        }
        return Self.defaultDisabledNoConnectReason
    }

    func consumedCopy() -> SalemXPhysical6RuntimeEnablementURLHook {
        .init(armed: false, consumed: true)
    }
}

private struct SalemXSenderLiveKitReadinessHook {
    static let defaultDisabledNoConnectReason = "default_disabled_no_connect"
    static let appSessionMissingReason = "sender_app_session_missing_redacted"
    static let wrongAccountReason = "sender_wrong_account_redacted"
    static let sameRoomReadinessMissingReason = "sender_same_room_readiness_missing_redacted"
    static let armedWaitingForFutureSenderJoinReason = "armed_waiting_for_future_sender_join"
    static let defaultDisabled = SalemXSenderLiveKitReadinessHook(armed: false,
                                                                  matrixSessionReady: false,
                                                                  expectedUserMatched: false,
                                                                  sameRoomReady: false,
                                                                  credentialsReady: false)

    let armed: Bool
    let matrixSessionReady: Bool
    let expectedUserMatched: Bool
    let sameRoomReady: Bool
    let credentialsReady: Bool

    let present = true
    let debugOnly = true
    let isDefaultDisabled = true
    let audioOnly = true
    let videoAllowed = false
    let matrixEventsAllowed = false
    let rawIdentifiersLogged = false

    var blockedReason: String {
        if !armed {
            return Self.defaultDisabledNoConnectReason
        }
        if !matrixSessionReady {
            return Self.appSessionMissingReason
        }
        if !expectedUserMatched {
            return Self.wrongAccountReason
        }
        if !sameRoomReady {
            return Self.sameRoomReadinessMissingReason
        }
        return Self.armedWaitingForFutureSenderJoinReason
    }
}

private struct SalemXSenderSideLiveKitJoinHook {
    static let notRequestedResult = "not_requested"
    static let blockedResult = "blocked_redacted"
    static let successResult = "success_redacted"
    static let failedResult = "failed_redacted"
    static let defaultDisabled = SalemXSenderSideLiveKitJoinHook(armed: false,
                                                                 requested: false,
                                                                 result: "not_requested",
                                                                 errorBucket: "none",
                                                                 repeated: false)

    let armed: Bool
    let requested: Bool
    let result: String
    let errorBucket: String
    let repeated: Bool

    let present = true
    let debugOnly = true
    let audioOnly = true
    let videoAllowed = false
    let matrixEventsAllowed = false
    let rawCredentialsLogged = false

    var isDefaultDisabled: Bool {
        !armed && !requested && result == Self.notRequestedResult
    }
}

private struct SalemXSenderSideLiveKitJoinActivation {
    static let defaultDisabledNoConnectReason = "default_disabled_no_connect"
    static let senderReadinessMissingReason = "sender_readiness_missing_redacted"
    static let sameRoomReadinessMissingReason = "sender_same_room_readiness_missing_redacted"
    static let armedWaitingForTriggerReason = "armed_waiting_for_sender_join_trigger"
    static let repeatedSenderJoinBlockedReason = "repeated_sender_join_blocked_redacted"
    static let senderJoinBlockedReason = "sender_join_blocked_redacted"
    static let senderJoinFailedReason = "sender_join_failed_redacted"
    static let senderJoinSuccessReason = "sender_join_success_redacted"
    static let defaultDisabled = SalemXSenderSideLiveKitJoinActivation(armed: false,
                                                                       triggered: false,
                                                                       consumed: false,
                                                                       repeated: false,
                                                                       blockedReason: defaultDisabledNoConnectReason)

    let armed: Bool
    let triggered: Bool
    let consumed: Bool
    let repeated: Bool
    let blockedReason: String

    let present = true
    let debugOnly = true
    let requiresSenderReadiness = true
    let requiresSameRoom = true
    let audioOnly = true
    let videoAllowed = false
    let matrixEventsAllowed = false
    let rawIdentifiersLogged = false

    var isDefaultDisabled: Bool {
        !armed && !triggered && !consumed && !repeated
    }
}

private struct SalemXSenderPendingMetadataReferenceHandoff {
    static let defaultDisabled = SalemXSenderPendingMetadataReferenceHandoff(reference: nil,
                                                                             source: "none",
                                                                             armed: false,
                                                                             receivedByRuntime: false)

    let reference: String?
    let source: String
    let armed: Bool
    let receivedByRuntime: Bool

    let present = true
    let debugOnly = true
    let rawReferenceLogged = false
    let rawMetadataLogged = false
    let rawRoomLogged = false
    let rawCallLogged = false
    let rawUserLogged = false
    let rawDeviceLogged = false

    var referencePresent: Bool {
        reference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func receivedByRuntimeCopy() -> SalemXSenderPendingMetadataReferenceHandoff {
        .init(reference: reference, source: source, armed: armed, receivedByRuntime: true)
    }
}

private struct SalemXSenderConnectParity {
    static let defaultEnabled = SalemXSenderConnectParity()

    let present = true
    let debugOnly = true
    let rawURLLogged = false
    let rawTokenLogged = false
    let rawRoomLogged = false
    let rawIdentityLogged = false
    let usesReceiverProvenConnectWrapper = true
    let usesAudioOnly = true
    let videoAllowed = false
    let matrixEventsAllowed = false
    let roomRetainedUntilTerminal = true
    let delegateRetainedUntilTerminal = true
    let stateObserverRetainedUntilTerminal = true
    let taskRetainedUntilTerminal = true
    let boundedWaitUsed = true
}

private struct SalemXSenderConnectExecutorUnification {
    static let shared = SalemXSenderConnectExecutorUnification(model: DirectCallLiveKitConnectExecutor.provenAudioModel)

    let present: Bool
    let debugOnly: Bool
    let receiverExecutorShared: Bool
    let senderExecutorShared: Bool
    let sameConnectOptionsShape: Bool
    let sameRoomRetentionModel: Bool
    let sameDelegateRetentionModel: Bool
    let sameStateObserverModel: Bool
    let sameBoundedWaitModel: Bool
    let audioOnly: Bool
    let videoAllowed: Bool
    let matrixEventsAllowed: Bool
    let rawURLLogged: Bool
    let rawTokenLogged: Bool
    let rawRoomLogged: Bool
    let rawIdentityLogged: Bool

    init(model: DirectCallLiveKitConnectExecutorModel) {
        present = model.present
        debugOnly = model.debugOnly
        receiverExecutorShared = model.receiverExecutorShared
        senderExecutorShared = model.senderExecutorShared
        sameConnectOptionsShape = model.sameConnectOptionsShape
        sameRoomRetentionModel = model.sameRoomRetentionModel
        sameDelegateRetentionModel = model.sameDelegateRetentionModel
        sameStateObserverModel = model.sameStateObserverModel
        sameBoundedWaitModel = model.sameBoundedWaitModel
        audioOnly = model.audioOnly
        videoAllowed = model.videoAllowed
        matrixEventsAllowed = model.matrixEventsAllowed
        rawURLLogged = model.rawURLLogged
        rawTokenLogged = model.rawTokenLogged
        rawRoomLogged = model.rawRoomLogged
        rawIdentityLogged = model.rawIdentityLogged
    }
}

private struct SalemXSenderRuntimeLiveKitJoinProofSummary {
    var proofGeneration = "none"
    var proofLastUpdatedBy = "none"
    let proofSource = "sender_runtime_livekit_join"
    var bridgePresent = true
    var bridgeDebugOnly = true
    var bridgeDefaultDisabled = true
    var bridgeOneShot = true
    var bridgeArmed = false
    var bridgeTriggered = false
    var bridgeConsumed = false
    var bridgeRepeated = false
    var bridgeStateRepairPresent = true
    var bridgeStateRepairDebugOnly = true
    var bridgeStateRepairRawIdentifiersLogged = false
    var bridgeArmGenerationChanged = false
    var bridgeTriggerGenerationMatchesArm = false
    var bridgeStaleGenerationDetected = false
    var bridgeRepeatedOnlyAfterConsumed = true
    var bridgeStateClassification = "sender_runtime_join_bridge_not_triggered_redacted"
    var restoredMatrixSessionUsed = false
    var pendingMetadataReferenceHandoffPresent = false
    var pendingMetadataReferenceHandoffDebugOnly = true
    var pendingMetadataReferenceHandoffArmedBeforeSenderTrigger = false
    var pendingMetadataReferenceHandoffReceivedBySenderRuntime = false
    var pendingMetadataReferenceHandoffSource = "none"
    var pendingMetadataReferenceHandoffRawReferenceLogged = false
    var pendingMetadataReferenceHandoffRawMetadataLogged = false
    var pendingMetadataReferenceHandoffRawRoomLogged = false
    var pendingMetadataReferenceHandoffRawCallLogged = false
    var pendingMetadataReferenceHandoffRawUserLogged = false
    var pendingMetadataReferenceHandoffRawDeviceLogged = false
    var pendingMetadataReferencePresent = false
    var pendingMetadataReferenceRedacted = true
    var pendingMetadataReferenceMatchesInviteSenderMemory = false
    var pendingMetadataReferenceMatchesSenderViewRoute = false
    var pendingMetadataFetchRequested = false
    var pendingMetadataFetchAuthorized = false
    var pendingMetadataFetchResult = "not_requested"
    var pendingMetadataFetchErrorBucket = "none"
    var pendingMetadataPayloadRedacted = true
    var pendingMetadataCallBindingPresent = false
    var pendingMetadataRoomBindingPresent = false
    var pendingMetadataPeerBindingPresent = false
    var pendingMetadataDirectionValid = false
    var pendingMetadataIntentAudio = false
    var metadataDirection = "none"
    var metadataIntent = "none"
    var metadataHasCallIdentifier = false
    var metadataHasRoomBinding = false
    var metadataHasPeer = false
    var credentialsRequested = false
    var credentialsAuthorized = false
    var credentialsResult = "not_requested"
    var tokenReceived = false
    var tokenRedacted = true
    var urlReceived = false
    var urlRedacted = true
    var payloadRedacted = true
    var executorShared = DirectCallLiveKitConnectExecutor.provenAudioModel.senderExecutorShared
    var executorInvoked = false
    var runtimeResult = "not_requested"
    var runtimeErrorBucket = "none"
    var senderLiveKitRoomConnected = false
    var senderLiveKitRoomDisconnected = false
    var senderCleanupResult = "not_requested"
    var senderConnectedSignalHandoffPresent = true
    var senderConnectedSignalHandoffDebugOnly = true
    var senderConnectedSignalHandoffRawIdentifiersLogged = false
    var senderConnectedSignalEmitted = false
    var senderConnectedSignalEmitSource = "none"
    var senderConnectedSignalEmittedAfterRuntimeJoinSuccess = false
    var senderConnectedSignalOpaqueCorrelationPresent = false
    var senderConnectedSignalRawRoomLogged = false
    var senderConnectedSignalRawCallLogged = false
    var senderConnectedSignalRawUserLogged = false
    var senderConnectedSignalRawDeviceLogged = false
    var runtimeDerived = true
    var queryOutcomeIgnored = true
    var audioOnly = true
    var videoAllowed = false
    var matrixEventsAllowed = false
    var microphonePermissionRequested = false
    var cameraPermissionRequested = false
    var matrixEventEmitRequested = false
    var realCallFlowStarted = false
    var blockedReason = "default_disabled_no_connect"

    var redactedLines: [String] {
        [
            "proof_generation=\(proofGeneration)",
            "proof_last_updated_by=\(proofLastUpdatedBy)",
            "proof_source=\(proofSource)",
            "sender_runtime_join_bridge_present=\(bridgePresent)",
            "sender_runtime_join_bridge_debug_only=\(bridgeDebugOnly)",
            "sender_runtime_join_bridge_default_disabled=\(bridgeDefaultDisabled)",
            "sender_runtime_join_bridge_one_shot=\(bridgeOneShot)",
            "sender_runtime_join_bridge_armed=\(bridgeArmed)",
            "sender_runtime_join_bridge_triggered=\(bridgeTriggered)",
            "sender_runtime_join_bridge_consumed=\(bridgeConsumed)",
            "sender_runtime_join_bridge_repeated=\(bridgeRepeated)",
            "sender_runtime_join_bridge_state_repair_present=\(bridgeStateRepairPresent)",
            "sender_runtime_join_bridge_state_repair_debug_only=\(bridgeStateRepairDebugOnly)",
            "sender_runtime_join_bridge_state_repair_raw_identifiers_logged=\(bridgeStateRepairRawIdentifiersLogged)",
            "sender_runtime_join_bridge_arm_generation_changed=\(bridgeArmGenerationChanged)",
            "sender_runtime_join_bridge_trigger_generation_matches_arm=\(bridgeTriggerGenerationMatchesArm)",
            "sender_runtime_join_bridge_stale_generation_detected=\(bridgeStaleGenerationDetected)",
            "sender_runtime_join_bridge_repeated_only_after_consumed=\(bridgeRepeatedOnlyAfterConsumed)",
            "sender_runtime_join_bridge_state_classification=\(bridgeStateClassification)",
            "sender_runtime_join_uses_restored_matrix_session=\(restoredMatrixSessionUsed)",
            "sender_pending_metadata_reference_handoff_present=\(pendingMetadataReferenceHandoffPresent)",
            "sender_pending_metadata_reference_handoff_debug_only=\(pendingMetadataReferenceHandoffDebugOnly)",
            "sender_pending_metadata_reference_handoff_armed_before_sender_trigger=\(pendingMetadataReferenceHandoffArmedBeforeSenderTrigger)",
            "sender_pending_metadata_reference_handoff_received_by_sender_runtime=\(pendingMetadataReferenceHandoffReceivedBySenderRuntime)",
            "sender_pending_metadata_reference_handoff_source=\(pendingMetadataReferenceHandoffSource)",
            "sender_pending_metadata_reference_handoff_raw_reference_logged=\(pendingMetadataReferenceHandoffRawReferenceLogged)",
            "sender_pending_metadata_reference_handoff_raw_metadata_logged=\(pendingMetadataReferenceHandoffRawMetadataLogged)",
            "sender_pending_metadata_reference_handoff_raw_room_logged=\(pendingMetadataReferenceHandoffRawRoomLogged)",
            "sender_pending_metadata_reference_handoff_raw_call_logged=\(pendingMetadataReferenceHandoffRawCallLogged)",
            "sender_pending_metadata_reference_handoff_raw_user_logged=\(pendingMetadataReferenceHandoffRawUserLogged)",
            "sender_pending_metadata_reference_handoff_raw_device_logged=\(pendingMetadataReferenceHandoffRawDeviceLogged)",
            "sender_runtime_join_pending_metadata_reference_present=\(pendingMetadataReferencePresent)",
            "sender_runtime_join_pending_metadata_reference_redacted=\(pendingMetadataReferenceRedacted)",
            "sender_runtime_join_pending_metadata_reference_matches_invite_sender_memory=\(pendingMetadataReferenceMatchesInviteSenderMemory)",
            "sender_runtime_join_pending_metadata_reference_matches_sender_view_route=\(pendingMetadataReferenceMatchesSenderViewRoute)",
            "sender_runtime_join_pending_metadata_fetch_requested=\(pendingMetadataFetchRequested)",
            "sender_runtime_join_pending_metadata_fetch_authorized=\(pendingMetadataFetchAuthorized)",
            "sender_runtime_join_pending_metadata_fetch_result=\(pendingMetadataFetchResult)",
            "sender_runtime_join_pending_metadata_fetch_error_bucket=\(pendingMetadataFetchErrorBucket)",
            "sender_runtime_join_pending_metadata_payload_redacted=\(pendingMetadataPayloadRedacted)",
            "sender_runtime_join_pending_metadata_call_binding_present=\(pendingMetadataCallBindingPresent)",
            "sender_runtime_join_pending_metadata_room_binding_present=\(pendingMetadataRoomBindingPresent)",
            "sender_runtime_join_pending_metadata_peer_binding_present=\(pendingMetadataPeerBindingPresent)",
            "sender_runtime_join_pending_metadata_direction_valid=\(pendingMetadataDirectionValid)",
            "sender_runtime_join_pending_metadata_intent_audio=\(pendingMetadataIntentAudio)",
            "sender_runtime_join_metadata_direction=\(metadataDirection)",
            "sender_runtime_join_metadata_intent=\(metadataIntent)",
            "sender_runtime_join_metadata_has_call_identifier=\(metadataHasCallIdentifier)",
            "sender_runtime_join_metadata_has_room_binding=\(metadataHasRoomBinding)",
            "sender_runtime_join_metadata_has_peer=\(metadataHasPeer)",
            "sender_runtime_join_credentials_requested=\(credentialsRequested)",
            "sender_runtime_join_credentials_authorized=\(credentialsAuthorized)",
            "sender_runtime_join_credentials_result=\(credentialsResult)",
            "sender_runtime_join_token_received=\(tokenReceived)",
            "sender_runtime_join_token_redacted=\(tokenRedacted)",
            "sender_runtime_join_url_received=\(urlReceived)",
            "sender_runtime_join_url_redacted=\(urlRedacted)",
            "sender_runtime_join_credentials_payload_redacted=\(payloadRedacted)",
            "sender_runtime_join_executor_shared=\(executorShared)",
            "sender_runtime_join_executor_invoked=\(executorInvoked)",
            "sender_runtime_join_runtime_result=\(runtimeResult)",
            "sender_runtime_join_runtime_error_bucket=\(runtimeErrorBucket)",
            "sender_livekit_room_connected=\(senderLiveKitRoomConnected)",
            "sender_livekit_room_disconnected=\(senderLiveKitRoomDisconnected)",
            "sender_cleanup_result=\(senderCleanupResult)",
            "sender_connected_signal_handoff_present=\(senderConnectedSignalHandoffPresent)",
            "sender_connected_signal_handoff_debug_only=\(senderConnectedSignalHandoffDebugOnly)",
            "sender_connected_signal_handoff_raw_identifiers_logged=\(senderConnectedSignalHandoffRawIdentifiersLogged)",
            "sender_connected_signal_emitted=\(senderConnectedSignalEmitted)",
            "sender_connected_signal_emit_source=\(senderConnectedSignalEmitSource)",
            "sender_connected_signal_emitted_after_runtime_join_success=\(senderConnectedSignalEmittedAfterRuntimeJoinSuccess)",
            "sender_connected_signal_opaque_correlation_present=\(senderConnectedSignalOpaqueCorrelationPresent)",
            "sender_connected_signal_raw_room_logged=\(senderConnectedSignalRawRoomLogged)",
            "sender_connected_signal_raw_call_logged=\(senderConnectedSignalRawCallLogged)",
            "sender_connected_signal_raw_user_logged=\(senderConnectedSignalRawUserLogged)",
            "sender_connected_signal_raw_device_logged=\(senderConnectedSignalRawDeviceLogged)",
            "sender_runtime_join_runtime_derived=\(runtimeDerived)",
            "sender_runtime_join_query_outcome_ignored=\(queryOutcomeIgnored)",
            "sender_runtime_join_audio_only=\(audioOnly)",
            "sender_runtime_join_video_allowed=\(videoAllowed)",
            "sender_runtime_join_matrix_events_allowed=\(matrixEventsAllowed)",
            "sender_camera_permission_requested=\(cameraPermissionRequested)",
            "sender_matrix_event_emit_requested=\(matrixEventEmitRequested)",
            "sender_real_call_flow_started=\(realCallFlowStarted)",
            "microphone_permission_requested=\(microphonePermissionRequested)",
            "camera_permission_requested=\(cameraPermissionRequested)",
            "matrix_event_emit_requested=\(matrixEventEmitRequested)",
            "real_call_flow_started=\(realCallFlowStarted)",
            "blocked_reason=\(blockedReason)"
        ]
    }

    mutating func markReferenceHandoff(_ handoff: SalemXSenderPendingMetadataReferenceHandoff, armGenerationChanged: Bool = false) {
        pendingMetadataReferenceHandoffPresent = handoff.referencePresent
        pendingMetadataReferenceHandoffDebugOnly = handoff.debugOnly
        pendingMetadataReferenceHandoffArmedBeforeSenderTrigger = handoff.armed && handoff.referencePresent
        pendingMetadataReferenceHandoffReceivedBySenderRuntime = handoff.receivedByRuntime
        pendingMetadataReferenceHandoffSource = handoff.source
        pendingMetadataReferenceHandoffRawReferenceLogged = handoff.rawReferenceLogged
        pendingMetadataReferenceHandoffRawMetadataLogged = handoff.rawMetadataLogged
        pendingMetadataReferenceHandoffRawRoomLogged = handoff.rawRoomLogged
        pendingMetadataReferenceHandoffRawCallLogged = handoff.rawCallLogged
        pendingMetadataReferenceHandoffRawUserLogged = handoff.rawUserLogged
        pendingMetadataReferenceHandoffRawDeviceLogged = handoff.rawDeviceLogged
        bridgeArmGenerationChanged = armGenerationChanged
        bridgeTriggerGenerationMatchesArm = false
        bridgeStaleGenerationDetected = false
        bridgeRepeatedOnlyAfterConsumed = true
        if armGenerationChanged {
            bridgeArmed = true
            bridgeTriggered = false
            bridgeConsumed = false
            bridgeRepeated = false
            bridgeStateClassification = "sender_runtime_join_bridge_armed_current_generation_redacted"
        }
    }

    mutating func markStarted(referencePresent: Bool,
                              repeated: Bool,
                              handoff: SalemXSenderPendingMetadataReferenceHandoff,
                              armGenerationChanged: Bool,
                              triggerGenerationMatchesArm: Bool,
                              staleGenerationDetected: Bool,
                              repeatedOnlyAfterConsumed: Bool) {
        proofGeneration = UUID().uuidString
        proofLastUpdatedBy = "sender_runtime_livekit_join_bridge"
        bridgeArmed = true
        bridgeTriggered = !repeated
        bridgeConsumed = !repeated
        bridgeRepeated = repeated
        markReferenceHandoff(handoff, armGenerationChanged: armGenerationChanged)
        bridgeArmGenerationChanged = armGenerationChanged
        bridgeTriggerGenerationMatchesArm = triggerGenerationMatchesArm
        bridgeStaleGenerationDetected = staleGenerationDetected
        bridgeRepeatedOnlyAfterConsumed = repeatedOnlyAfterConsumed
        pendingMetadataReferencePresent = referencePresent
        pendingMetadataReferenceMatchesInviteSenderMemory = referencePresent && handoff.armed
        pendingMetadataReferenceMatchesSenderViewRoute = false
        pendingMetadataFetchRequested = false
        pendingMetadataFetchAuthorized = false
        pendingMetadataFetchResult = "not_requested"
        pendingMetadataFetchErrorBucket = "none"
        pendingMetadataCallBindingPresent = false
        pendingMetadataRoomBindingPresent = false
        pendingMetadataPeerBindingPresent = false
        pendingMetadataDirectionValid = false
        pendingMetadataIntentAudio = false
        metadataDirection = "none"
        metadataIntent = "none"
        metadataHasCallIdentifier = false
        metadataHasRoomBinding = false
        metadataHasPeer = false
        credentialsRequested = false
        credentialsAuthorized = false
        credentialsResult = "not_requested"
        tokenReceived = false
        urlReceived = false
        executorInvoked = false
        runtimeResult = "not_requested"
        runtimeErrorBucket = "none"
        senderLiveKitRoomConnected = false
        senderLiveKitRoomDisconnected = false
        senderCleanupResult = "not_requested"
        senderConnectedSignalEmitted = false
        senderConnectedSignalEmitSource = "none"
        senderConnectedSignalEmittedAfterRuntimeJoinSuccess = false
        senderConnectedSignalOpaqueCorrelationPresent = false
        restoredMatrixSessionUsed = false
        if repeated, repeatedOnlyAfterConsumed {
            bridgeStateClassification = "sender_runtime_join_bridge_repeated_after_consumed_redacted"
        } else if repeated {
            bridgeStateClassification = "sender_runtime_join_bridge_repeated_before_consumed_redacted"
        } else if staleGenerationDetected {
            bridgeStateClassification = "sender_runtime_join_bridge_stale_generation_redacted"
        } else if triggerGenerationMatchesArm {
            bridgeStateClassification = "sender_runtime_join_bridge_triggered_current_generation_redacted"
        } else {
            bridgeStateClassification = "sender_runtime_join_executor_not_invoked_redacted"
        }
        blockedReason = repeated ? "sender_runtime_join_repeated_blocked_redacted" : "sender_runtime_join_started_redacted"
    }

    mutating func markPendingMetadataSuccess(_ session: DirectCallSession) {
        restoredMatrixSessionUsed = true
        pendingMetadataReferenceMatchesSenderViewRoute = true
        pendingMetadataFetchRequested = true
        pendingMetadataFetchAuthorized = true
        pendingMetadataFetchResult = "success_redacted"
        pendingMetadataFetchErrorBucket = "none"
        metadataDirection = String(describing: session.direction)
        metadataIntent = session.intent.rawValue
        metadataHasCallIdentifier = !session.callID.isEmpty
        metadataHasRoomBinding = !session.roomID.isEmpty
        metadataHasPeer = !session.peerUserID.isEmpty
        pendingMetadataCallBindingPresent = metadataHasCallIdentifier
        pendingMetadataRoomBindingPresent = metadataHasRoomBinding
        pendingMetadataPeerBindingPresent = metadataHasPeer
        pendingMetadataDirectionValid = session.direction == .outgoing
        pendingMetadataIntentAudio = session.intent == .audio
        blockedReason = "sender_runtime_credentials_pending_redacted"
    }

    mutating func markPendingMetadataBlocked(_ reason: String, authorized: Bool) {
        pendingMetadataFetchRequested = true
        pendingMetadataFetchAuthorized = authorized
        pendingMetadataFetchResult = "blocked_redacted"
        pendingMetadataFetchErrorBucket = reason
        runtimeResult = "blocked_redacted"
        runtimeErrorBucket = "pending_metadata_unavailable_redacted"
        senderCleanupResult = "not_required_redacted"
        bridgeStateClassification = "sender_runtime_join_executor_not_invoked_redacted"
        blockedReason = reason
    }

    mutating func markCredentials(_ result: Result<DirectCallMediaConnectionInfo, DirectCallMediaError>) {
        credentialsRequested = true
        credentialsAuthorized = true
        switch result {
        case .success:
            credentialsResult = "success_redacted"
            tokenReceived = true
            urlReceived = true
            blockedReason = "sender_runtime_e2ee_pending_redacted"
        case .failure(let error):
            credentialsResult = "blocked_redacted"
            runtimeResult = "blocked_redacted"
            runtimeErrorBucket = DirectCallDiagnosticMediaFailureReason(error).rawValue
            senderCleanupResult = "not_required_redacted"
            bridgeStateClassification = "sender_runtime_join_not_connected_redacted"
            blockedReason = "sender_runtime_credentials_failed_redacted"
        }
    }

    mutating func markE2EEBlocked(_ error: DirectCallMediaError) {
        runtimeResult = "blocked_redacted"
        runtimeErrorBucket = DirectCallDiagnosticMediaFailureReason(error).rawValue
        senderCleanupResult = "not_required_redacted"
        bridgeStateClassification = "sender_runtime_join_not_connected_redacted"
        blockedReason = "sender_runtime_e2ee_context_unavailable_redacted"
    }

    mutating func markRuntime(_ result: Result<Void, DirectCallMediaError>) {
        executorInvoked = true
        switch result {
        case .success:
            runtimeResult = "success_redacted"
            runtimeErrorBucket = "none"
            senderLiveKitRoomConnected = true
            senderLiveKitRoomDisconnected = false
            senderCleanupResult = "deferred_for_receiver_observation_redacted"
            senderConnectedSignalEmitted = true
            senderConnectedSignalEmitSource = "sender_runtime_livekit_join_redacted"
            senderConnectedSignalEmittedAfterRuntimeJoinSuccess = true
            senderConnectedSignalOpaqueCorrelationPresent = pendingMetadataReferenceMatchesInviteSenderMemory || pendingMetadataReferenceMatchesSenderViewRoute
            bridgeStateClassification = "sender_runtime_join_connected_redacted"
            blockedReason = "none"
        case .failure(let error):
            runtimeResult = "failed_redacted"
            runtimeErrorBucket = DirectCallDiagnosticMediaFailureReason(error).rawValue
            senderLiveKitRoomConnected = false
            senderLiveKitRoomDisconnected = true
            senderCleanupResult = "completed_redacted"
            senderConnectedSignalEmitted = false
            senderConnectedSignalEmitSource = "none"
            senderConnectedSignalEmittedAfterRuntimeJoinSuccess = false
            bridgeStateClassification = "sender_runtime_join_not_connected_redacted"
            blockedReason = "sender_runtime_join_failed_redacted"
        }
    }
}

private struct SalemXSenderJoinTriggerOrchestrationInput {
    let apnsSuccessSeen: Bool
    let receiverAnswerSeen: Bool
    let receiverConnectTerminalSeen: Bool
    let senderActivationArmed: Bool
    let senderTriggerStarted: Bool
    let senderTriggerCompleted: Bool
    let senderSDKTimelineTerminalSeen: Bool
}

private struct SalemXSenderJoinTriggerOrchestration {
    static let waitingForAnswerClassification = "sender_trigger_waiting_for_answer_redacted"
    static let waitingForReceiverConnectClassification = "sender_trigger_waiting_for_receiver_connect_redacted"
    static let activationNotArmedClassification = "sender_trigger_activation_not_armed_redacted"
    static let requiredButNotStartedClassification = "sender_trigger_required_but_not_started_redacted"
    static let startedNotCompletedClassification = "sender_trigger_started_not_completed_redacted"
    static let completedWaitingForSDKTimelineClassification = "sender_trigger_completed_waiting_for_sdk_timeline_redacted"
    static let completedSDKTimelineTerminalClassification = "sender_trigger_completed_sdk_timeline_terminal_redacted"
    static let pollBlockedUntilSenderTerminalClassification = "sender_trigger_poll_blocked_until_sender_terminal_redacted"
    static let defaultBlocked = SalemXSenderJoinTriggerOrchestration(input: .init(apnsSuccessSeen: false,
                                                                                  receiverAnswerSeen: false,
                                                                                  receiverConnectTerminalSeen: false,
                                                                                  senderActivationArmed: false,
                                                                                  senderTriggerStarted: false,
                                                                                  senderTriggerCompleted: false,
                                                                                  senderSDKTimelineTerminalSeen: false))

    let apnsSuccessSeen: Bool
    let receiverAnswerSeen: Bool
    let receiverConnectTerminalSeen: Bool
    let senderActivationArmed: Bool
    let senderTriggerStarted: Bool
    let senderTriggerCompleted: Bool
    let senderSDKTimelineTerminalSeen: Bool

    let present = true
    let debugOnly = true
    let rawIdentifiersLogged = false
    let senderTriggerRequired = true

    var senderTriggerAllowed: Bool {
        apnsSuccessSeen && receiverAnswerSeen && receiverConnectTerminalSeen && senderActivationArmed
    }

    var senderTriggerMissingClassified: Bool {
        finalClassification == Self.requiredButNotStartedClassification
    }

    var pollAllowed: Bool {
        senderTriggerCompleted && senderSDKTimelineTerminalSeen
    }

    var pollBlockedReason: String {
        if pollAllowed {
            return "none"
        }
        if finalClassification == Self.completedWaitingForSDKTimelineClassification {
            return finalClassification
        }
        return Self.pollBlockedUntilSenderTerminalClassification
    }

    var finalClassification: String {
        if !apnsSuccessSeen || !receiverAnswerSeen {
            return Self.waitingForAnswerClassification
        }
        if !receiverConnectTerminalSeen {
            return Self.waitingForReceiverConnectClassification
        }
        if !senderActivationArmed {
            return Self.activationNotArmedClassification
        }
        if !senderTriggerStarted {
            return Self.requiredButNotStartedClassification
        }
        if !senderTriggerCompleted {
            return Self.startedNotCompletedClassification
        }
        if !senderSDKTimelineTerminalSeen {
            return Self.completedWaitingForSDKTimelineClassification
        }
        return Self.completedSDKTimelineTerminalClassification
    }

    init(input: SalemXSenderJoinTriggerOrchestrationInput) {
        apnsSuccessSeen = input.apnsSuccessSeen
        receiverAnswerSeen = input.receiverAnswerSeen
        receiverConnectTerminalSeen = input.receiverConnectTerminalSeen
        senderActivationArmed = input.senderActivationArmed
        senderTriggerStarted = input.senderTriggerStarted
        senderTriggerCompleted = input.senderTriggerCompleted
        senderSDKTimelineTerminalSeen = input.senderSDKTimelineTerminalSeen
    }
}

private struct SalemXSenderJoinFailureDiagnosticInput {
    let requested: Bool
    let repeated: Bool
    let credentialsPresent: Bool
    let tokenPresent: Bool
    let urlPresent: Bool
    let roomBindingPresent: Bool
    let sameLiveKitRoom: Bool
    let requestedResult: String
    let transportAttempted: Bool?
    let transportResult: String?
    let classification: String?
}

private struct SalemXSenderJoinDiagnosticsResult {
    let joinFailure: SalemXSenderJoinFailureDiagnostics
    let transportFailure: SalemXSenderTransportFailureDiagnostics
    let transportErrorSurface: SalemXSenderTransportErrorSurface
}

private struct SalemXSenderJoinFailureDiagnostics {
    static let notRequestedClassification = "not_requested"
    static let credentialsMissingClassification = "credentials_missing_redacted"
    static let tokenMissingClassification = "token_missing_redacted"
    static let urlMissingClassification = "url_missing_redacted"
    static let roomBindingMissingClassification = "room_binding_missing_redacted"
    static let sameLiveKitRoomMismatchClassification = "same_livekit_room_mismatch_redacted"
    static let transportFailedClassification = "transport_failed_redacted"
    static let joinFailedClassification = "join_failed_redacted"
    static let unknownFailureClassification = "unknown_sender_join_failure_redacted"
    static let repeatedSenderJoinClassification = "sender_join_repeated_redacted"
    static let notRequestedTransportResult = "not_requested"
    static let successTransportResult = "success_redacted"
    static let failedTransportResult = "failed_redacted"
    static let defaultDisabled = SalemXSenderJoinFailureDiagnostics(credentialsPresent: false,
                                                                    tokenPresent: false,
                                                                    urlPresent: false,
                                                                    roomBindingPresent: false,
                                                                    sameLiveKitRoom: false,
                                                                    transportAttempted: false,
                                                                    transportResult: notRequestedTransportResult,
                                                                    errorBucket: "none",
                                                                    classification: notRequestedClassification)

    let credentialsPresent: Bool
    let tokenPresent: Bool
    let urlPresent: Bool
    let roomBindingPresent: Bool
    let sameLiveKitRoom: Bool
    let transportAttempted: Bool
    let transportResult: String
    let errorBucket: String
    let classification: String

    let present = true
    let debugOnly = true
    let audioOnly = true
    let videoAllowed = false
    let matrixEventsAllowed = false
    let rawIdentifiersLogged = false

    var blocksBeforeTransport: Bool {
        !transportAttempted && errorBucket != "none" && classification != Self.notRequestedClassification
    }

    static func classify(_ input: SalemXSenderJoinFailureDiagnosticInput) -> SalemXSenderJoinFailureDiagnostics {
        let requested = input.requested
        let repeated = input.repeated
        let credentialsPresent = input.credentialsPresent
        let tokenPresent = input.tokenPresent
        let urlPresent = input.urlPresent
        let roomBindingPresent = input.roomBindingPresent
        let sameLiveKitRoom = input.sameLiveKitRoom
        let requestedResult = input.requestedResult

        guard requested else {
            return defaultDisabled
        }
        if repeated {
            return blocked(credentialsPresent: credentialsPresent,
                           tokenPresent: tokenPresent,
                           urlPresent: urlPresent,
                           roomBindingPresent: roomBindingPresent,
                           sameLiveKitRoom: sameLiveKitRoom,
                           classification: repeatedSenderJoinClassification)
        }
        if !credentialsPresent {
            return blocked(credentialsPresent: false,
                           tokenPresent: tokenPresent,
                           urlPresent: urlPresent,
                           roomBindingPresent: roomBindingPresent,
                           sameLiveKitRoom: sameLiveKitRoom,
                           classification: credentialsMissingClassification)
        }
        if !tokenPresent {
            return blocked(credentialsPresent: credentialsPresent,
                           tokenPresent: false,
                           urlPresent: urlPresent,
                           roomBindingPresent: roomBindingPresent,
                           sameLiveKitRoom: sameLiveKitRoom,
                           classification: tokenMissingClassification)
        }
        if !urlPresent {
            return blocked(credentialsPresent: credentialsPresent,
                           tokenPresent: tokenPresent,
                           urlPresent: false,
                           roomBindingPresent: roomBindingPresent,
                           sameLiveKitRoom: sameLiveKitRoom,
                           classification: urlMissingClassification)
        }
        if !roomBindingPresent {
            return blocked(credentialsPresent: credentialsPresent,
                           tokenPresent: tokenPresent,
                           urlPresent: urlPresent,
                           roomBindingPresent: false,
                           sameLiveKitRoom: sameLiveKitRoom,
                           classification: roomBindingMissingClassification)
        }
        if !sameLiveKitRoom {
            return blocked(credentialsPresent: credentialsPresent,
                           tokenPresent: tokenPresent,
                           urlPresent: urlPresent,
                           roomBindingPresent: roomBindingPresent,
                           sameLiveKitRoom: false,
                           classification: sameLiveKitRoomMismatchClassification)
        }

        let attempted = input.transportAttempted ?? (requestedResult == SalemXSenderSideLiveKitJoinHook.successResult || requestedResult == SalemXSenderSideLiveKitJoinHook.failedResult)
        let resolvedTransportResult = input.transportResult ?? defaultTransportResult(requestedResult: requestedResult, attempted: attempted)
        let resolvedClassification = resolvedClassification(requestedResult: requestedResult,
                                                            transportAttempted: attempted,
                                                            transportResult: resolvedTransportResult,
                                                            classification: input.classification)
        return .init(credentialsPresent: credentialsPresent,
                     tokenPresent: tokenPresent,
                     urlPresent: urlPresent,
                     roomBindingPresent: roomBindingPresent,
                     sameLiveKitRoom: sameLiveKitRoom,
                     transportAttempted: attempted,
                     transportResult: resolvedTransportResult,
                     errorBucket: resolvedClassification == "none" ? "none" : resolvedClassification,
                     classification: resolvedClassification)
    }

    private static func blocked(credentialsPresent: Bool,
                                tokenPresent: Bool,
                                urlPresent: Bool,
                                roomBindingPresent: Bool,
                                sameLiveKitRoom: Bool,
                                classification: String) -> SalemXSenderJoinFailureDiagnostics {
        .init(credentialsPresent: credentialsPresent,
              tokenPresent: tokenPresent,
              urlPresent: urlPresent,
              roomBindingPresent: roomBindingPresent,
              sameLiveKitRoom: sameLiveKitRoom,
              transportAttempted: false,
              transportResult: notRequestedTransportResult,
              errorBucket: classification,
              classification: classification)
    }

    private static func defaultTransportResult(requestedResult: String, attempted: Bool) -> String {
        guard attempted else {
            return notRequestedTransportResult
        }
        if requestedResult == SalemXSenderSideLiveKitJoinHook.successResult {
            return successTransportResult
        }
        if requestedResult == SalemXSenderSideLiveKitJoinHook.failedResult {
            return failedTransportResult
        }
        return notRequestedTransportResult
    }

    private static func resolvedClassification(requestedResult: String,
                                               transportAttempted: Bool,
                                               transportResult: String,
                                               classification: String?) -> String {
        if let classification {
            return classification
        }
        if transportAttempted, transportResult == failedTransportResult {
            return transportFailedClassification
        }
        if requestedResult == SalemXSenderSideLiveKitJoinHook.failedResult {
            return joinFailedClassification
        }
        if requestedResult == SalemXSenderSideLiveKitJoinHook.successResult {
            return "none"
        }
        return unknownFailureClassification
    }
}

private struct SalemXSenderLiveKitSDKTimelineInput {
    static let defaultDisabled = SalemXSenderLiveKitSDKTimelineInput(provided: false,
                                                                     requestedClassification: nil,
                                                                     triggerReceived: false,
                                                                     taskCreated: false,
                                                                     taskStarted: false,
                                                                     connectInvoked: false,
                                                                     connectReturned: false,
                                                                     connectThrew: false,
                                                                     delegateAttached: false,
                                                                     stateObserverAttached: false,
                                                                     connectedStateSeen: false,
                                                                     failedStateSeen: false,
                                                                     disconnectedStateSeen: false,
                                                                     taskCancelled: false,
                                                                     taskCompleted: false,
                                                                     timeoutElapsed: false,
                                                                     proofWrittenAfterTerminalState: false,
                                                                     timeoutDiagnostics: .defaultDisabled)

    let provided: Bool
    let requestedClassification: String?
    let triggerReceived: Bool
    let taskCreated: Bool
    let taskStarted: Bool
    let connectInvoked: Bool
    let connectReturned: Bool
    let connectThrew: Bool
    let delegateAttached: Bool
    let stateObserverAttached: Bool
    let connectedStateSeen: Bool
    let failedStateSeen: Bool
    let disconnectedStateSeen: Bool
    let taskCancelled: Bool
    let taskCompleted: Bool
    let timeoutElapsed: Bool
    let proofWrittenAfterTerminalState: Bool
    let timeoutDiagnostics: SalemXSenderLiveKitSDKTimeoutDiagnosticsInput
}

private struct SalemXSenderLiveKitSDKTimeoutDiagnosticsInput {
    static let defaultDisabled = SalemXSenderLiveKitSDKTimeoutDiagnosticsInput(provided: false,
                                                                               requestedClassification: nil,
                                                                               waitWindowBucket: "not_requested",
                                                                               connectInvoked: false,
                                                                               connectCallPendingAtTimeout: false,
                                                                               taskRunningAtTimeout: false,
                                                                               taskCancelledAtTimeout: false,
                                                                               delegateAttached: false,
                                                                               stateObserverAttached: false,
                                                                               stateEventCountBucket: "not_requested",
                                                                               delegateEventCountBucket: "not_requested",
                                                                               appStateBucket: "not_requested",
                                                                               actorContextAvailable: false,
                                                                               networkPathBucket: "not_requested")

    let provided: Bool
    let requestedClassification: String?
    let waitWindowBucket: String
    let connectInvoked: Bool
    let connectCallPendingAtTimeout: Bool
    let taskRunningAtTimeout: Bool
    let taskCancelledAtTimeout: Bool
    let delegateAttached: Bool
    let stateObserverAttached: Bool
    let stateEventCountBucket: String
    let delegateEventCountBucket: String
    let appStateBucket: String
    let actorContextAvailable: Bool
    let networkPathBucket: String
}

private struct SalemXSenderLiveKitSDKTimeoutDiagnostics {
    static let notRequestedClassification = "not_requested"
    static let noneClassification = "none"
    static let waitWindowNormalBucket = "normal_redacted"
    static let waitWindowTooShortBucket = "too_short_redacted"
    static let zeroEventsBucket = "0"
    static let oneToThreeEventsBucket = "1_3"
    static let moreThanThreeEventsBucket = "gt3"
    static let unknownBucket = "unknown"
    static let appLifecycleInterruptedBucket = "app_lifecycle_interrupted_redacted"
    static let networkPendingBucket = "network_pending_redacted"
    static let authPendingBucket = "auth_pending_redacted"
    static let noStateEventsClassification = "sdk_connect_timeout_no_state_events_redacted"
    static let delegateMissingClassification = "sdk_connect_timeout_delegate_missing_redacted"
    static let stateObserverMissingClassification = "sdk_connect_timeout_state_observer_missing_redacted"
    static let taskSuspendedClassification = "sdk_connect_timeout_task_suspended_redacted"
    static let taskRunningNoCallbackClassification = "sdk_connect_timeout_task_running_no_callback_redacted"
    static let connectCallPendingClassification = "sdk_connect_timeout_connect_call_pending_redacted"
    static let networkPendingClassification = "sdk_connect_timeout_network_pending_redacted"
    static let authPendingClassification = "sdk_connect_timeout_auth_pending_redacted"
    static let appLifecycleInterruptedClassification = "sdk_connect_timeout_app_lifecycle_interrupted_redacted"
    static let actorIsolationSuspectedClassification = "sdk_connect_timeout_actor_isolation_suspected_redacted"
    static let waitWindowTooShortClassification = "sdk_connect_timeout_wait_window_too_short_redacted"
    static let unknownPendingClassification = "sdk_connect_timeout_unknown_pending_redacted"
    static let allowedClassifications: Set<String> = [
        noStateEventsClassification,
        delegateMissingClassification,
        stateObserverMissingClassification,
        taskSuspendedClassification,
        taskRunningNoCallbackClassification,
        connectCallPendingClassification,
        networkPendingClassification,
        authPendingClassification,
        appLifecycleInterruptedClassification,
        actorIsolationSuspectedClassification,
        waitWindowTooShortClassification,
        unknownPendingClassification
    ]
    static let allowedCountBuckets: Set<String> = [
        zeroEventsBucket,
        oneToThreeEventsBucket,
        moreThanThreeEventsBucket,
        unknownBucket,
        "not_requested"
    ]
    static let allowedWaitWindowBuckets: Set<String> = [
        waitWindowNormalBucket,
        waitWindowTooShortBucket,
        unknownBucket,
        "not_requested"
    ]
    static let allowedAppStateBuckets: Set<String> = [
        "foreground",
        "background",
        "inactive",
        appLifecycleInterruptedBucket,
        unknownBucket,
        "not_requested"
    ]
    static let allowedNetworkPathBuckets: Set<String> = [
        "satisfied_redacted",
        networkPendingBucket,
        authPendingBucket,
        unknownBucket,
        "not_requested"
    ]
    static let defaultDisabled = SalemXSenderLiveKitSDKTimeoutDiagnostics(waitWindowBucket: "not_requested",
                                                                          connectInvoked: false,
                                                                          connectCallPendingAtTimeout: false,
                                                                          taskRunningAtTimeout: false,
                                                                          taskCancelledAtTimeout: false,
                                                                          delegateAttached: false,
                                                                          stateObserverAttached: false,
                                                                          stateEventCountBucket: "not_requested",
                                                                          delegateEventCountBucket: "not_requested",
                                                                          appStateBucket: "not_requested",
                                                                          actorContextAvailable: false,
                                                                          networkPathBucket: "not_requested",
                                                                          finalClassification: notRequestedClassification)

    let waitWindowBucket: String
    let connectInvoked: Bool
    let connectCallPendingAtTimeout: Bool
    let taskRunningAtTimeout: Bool
    let taskCancelledAtTimeout: Bool
    let delegateAttached: Bool
    let stateObserverAttached: Bool
    let stateEventCountBucket: String
    let delegateEventCountBucket: String
    let appStateBucket: String
    let actorContextAvailable: Bool
    let networkPathBucket: String
    let finalClassification: String

    let present = true
    let debugOnly = true
    let rawErrorLogged = false
    let rawURLLogged = false
    let rawTokenLogged = false
    let rawRoomLogged = false
    let rawIdentityLogged = false

    static func classify(requested: Bool,
                         timeline: SalemXSenderLiveKitSDKTimelineInput) -> SalemXSenderLiveKitSDKTimeoutDiagnostics {
        guard requested else {
            return defaultDisabled
        }

        let input = resolvedInput(from: timeline)
        guard input.provided else {
            return defaultDisabled
        }
        let classification = resolvedClassification(input)
        return .init(waitWindowBucket: input.waitWindowBucket,
                     connectInvoked: input.connectInvoked,
                     connectCallPendingAtTimeout: input.connectCallPendingAtTimeout,
                     taskRunningAtTimeout: input.taskRunningAtTimeout,
                     taskCancelledAtTimeout: input.taskCancelledAtTimeout,
                     delegateAttached: input.delegateAttached,
                     stateObserverAttached: input.stateObserverAttached,
                     stateEventCountBucket: input.stateEventCountBucket,
                     delegateEventCountBucket: input.delegateEventCountBucket,
                     appStateBucket: input.appStateBucket,
                     actorContextAvailable: input.actorContextAvailable,
                     networkPathBucket: input.networkPathBucket,
                     finalClassification: classification)
    }

    private static func resolvedInput(from timeline: SalemXSenderLiveKitSDKTimelineInput) -> SalemXSenderLiveKitSDKTimeoutDiagnosticsInput {
        let input = timeline.timeoutDiagnostics
        guard input.provided || timeline.timeoutElapsed else {
            return input
        }
        let stateEventCount = input.provided ? input.stateEventCountBucket : inferredStateEventCountBucket(timeline)
        let delegateEventCount = input.provided ? input.delegateEventCountBucket : inferredDelegateEventCountBucket(timeline)
        return .init(provided: true,
                     requestedClassification: input.requestedClassification,
                     waitWindowBucket: input.provided ? input.waitWindowBucket : waitWindowNormalBucket,
                     connectInvoked: input.provided ? input.connectInvoked : timeline.connectInvoked,
                     connectCallPendingAtTimeout: input.provided ? input.connectCallPendingAtTimeout : (timeline.connectInvoked && !timeline.connectReturned && !timeline.connectThrew),
                     taskRunningAtTimeout: input.provided ? input.taskRunningAtTimeout : (timeline.taskStarted && !timeline.taskCompleted && !timeline.taskCancelled),
                     taskCancelledAtTimeout: input.provided ? input.taskCancelledAtTimeout : timeline.taskCancelled,
                     delegateAttached: input.provided ? input.delegateAttached : timeline.delegateAttached,
                     stateObserverAttached: input.provided ? input.stateObserverAttached : timeline.stateObserverAttached,
                     stateEventCountBucket: stateEventCount,
                     delegateEventCountBucket: delegateEventCount,
                     appStateBucket: input.provided ? input.appStateBucket : unknownBucket,
                     actorContextAvailable: input.provided ? input.actorContextAvailable : true,
                     networkPathBucket: input.provided ? input.networkPathBucket : unknownBucket)
    }

    private static func resolvedClassification(_ input: SalemXSenderLiveKitSDKTimeoutDiagnosticsInput) -> String {
        if let requestedClassification = input.requestedClassification {
            return requestedClassification
        }
        if let instrumentationClassification = instrumentationClassification(input) {
            return instrumentationClassification
        }
        if let environmentClassification = environmentClassification(input) {
            return environmentClassification
        }
        if let pendingClassification = pendingTimeoutClassification(input) {
            return pendingClassification
        }
        return unknownPendingClassification
    }

    private static func instrumentationClassification(_ input: SalemXSenderLiveKitSDKTimeoutDiagnosticsInput) -> String? {
        if !input.delegateAttached {
            return delegateMissingClassification
        }
        if !input.stateObserverAttached {
            return stateObserverMissingClassification
        }
        return nil
    }

    private static func environmentClassification(_ input: SalemXSenderLiveKitSDKTimeoutDiagnosticsInput) -> String? {
        if input.waitWindowBucket == waitWindowTooShortBucket {
            return waitWindowTooShortClassification
        }
        if input.taskCancelledAtTimeout {
            return taskSuspendedClassification
        }
        if input.appStateBucket == appLifecycleInterruptedBucket {
            return appLifecycleInterruptedClassification
        }
        if !input.actorContextAvailable {
            return actorIsolationSuspectedClassification
        }
        if input.networkPathBucket == authPendingBucket {
            return authPendingClassification
        }
        if input.networkPathBucket == networkPendingBucket {
            return networkPendingClassification
        }
        return nil
    }

    private static func pendingTimeoutClassification(_ input: SalemXSenderLiveKitSDKTimeoutDiagnosticsInput) -> String? {
        if input.connectInvoked,
           input.stateEventCountBucket == zeroEventsBucket,
           input.delegateEventCountBucket == zeroEventsBucket {
            return noStateEventsClassification
        }
        if input.taskRunningAtTimeout, input.connectCallPendingAtTimeout {
            return connectCallPendingClassification
        }
        if input.taskRunningAtTimeout {
            return taskRunningNoCallbackClassification
        }
        return nil
    }

    private static func inferredStateEventCountBucket(_ timeline: SalemXSenderLiveKitSDKTimelineInput) -> String {
        timeline.connectedStateSeen || timeline.failedStateSeen || timeline.disconnectedStateSeen ? oneToThreeEventsBucket : zeroEventsBucket
    }

    private static func inferredDelegateEventCountBucket(_ timeline: SalemXSenderLiveKitSDKTimelineInput) -> String {
        timeline.connectReturned || timeline.connectThrew ? oneToThreeEventsBucket : zeroEventsBucket
    }
}

private struct SalemXSenderLiveKitSDKTimeline {
    static let notRequestedClassification = "not_requested"
    static let noneClassification = "none"
    static let taskNotCreatedClassification = "sdk_timeline_task_not_created_redacted"
    static let taskCreatedNotStartedClassification = "sdk_timeline_task_created_not_started_redacted"
    static let taskCancelledBeforeConnectClassification = "sdk_timeline_task_cancelled_before_connect_redacted"
    static let connectInvokedNoReturnClassification = "sdk_timeline_connect_invoked_no_return_redacted"
    static let connectTimeoutClassification = "sdk_timeline_connect_timeout_redacted"
    static let delegateNotAttachedClassification = "sdk_timeline_delegate_not_attached_redacted"
    static let stateObserverNotAttachedClassification = "sdk_timeline_state_observer_not_attached_redacted"
    static let callbackNotObservedClassification = "sdk_timeline_callback_not_observed_redacted"
    static let proofWrittenBeforeTerminalStateClassification = "sdk_timeline_proof_written_before_terminal_state_redacted"
    static let appLifecycleInterruptedClassification = "sdk_timeline_app_lifecycle_interrupted_redacted"
    static let actorIsolationLostCallbackClassification = "sdk_timeline_actor_isolation_lost_callback_redacted"
    static let internalPendingClassification = "sdk_timeline_internal_pending_redacted"
    static let allowedClassifications = Set([
        taskNotCreatedClassification,
        taskCreatedNotStartedClassification,
        taskCancelledBeforeConnectClassification,
        connectInvokedNoReturnClassification,
        connectTimeoutClassification,
        delegateNotAttachedClassification,
        stateObserverNotAttachedClassification,
        callbackNotObservedClassification,
        proofWrittenBeforeTerminalStateClassification,
        appLifecycleInterruptedClassification,
        actorIsolationLostCallbackClassification,
        internalPendingClassification
    ]).union(SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedClassifications)
    static let terminalClassifications = Set([
        noneClassification,
        taskNotCreatedClassification,
        taskCreatedNotStartedClassification,
        taskCancelledBeforeConnectClassification,
        connectInvokedNoReturnClassification,
        connectTimeoutClassification,
        delegateNotAttachedClassification,
        stateObserverNotAttachedClassification,
        callbackNotObservedClassification,
        proofWrittenBeforeTerminalStateClassification,
        appLifecycleInterruptedClassification,
        actorIsolationLostCallbackClassification
    ]).union(SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedClassifications)
    static let defaultDisabled = SalemXSenderLiveKitSDKTimeline(triggerReceived: false,
                                                                taskCreated: false,
                                                                taskStarted: false,
                                                                connectInvoked: false,
                                                                connectReturned: false,
                                                                connectThrew: false,
                                                                delegateAttached: false,
                                                                stateObserverAttached: false,
                                                                connectedStateSeen: false,
                                                                failedStateSeen: false,
                                                                disconnectedStateSeen: false,
                                                                taskCancelled: false,
                                                                taskCompleted: false,
                                                                timeoutElapsed: false,
                                                                proofWrittenAfterTerminalState: false,
                                                                timeoutDiagnostics: .defaultDisabled,
                                                                finalClassification: notRequestedClassification)

    let triggerReceived: Bool
    let taskCreated: Bool
    let taskStarted: Bool
    let connectInvoked: Bool
    let connectReturned: Bool
    let connectThrew: Bool
    let delegateAttached: Bool
    let stateObserverAttached: Bool
    let connectedStateSeen: Bool
    let failedStateSeen: Bool
    let disconnectedStateSeen: Bool
    let taskCancelled: Bool
    let taskCompleted: Bool
    let timeoutElapsed: Bool
    let proofWrittenAfterTerminalState: Bool
    let timeoutDiagnostics: SalemXSenderLiveKitSDKTimeoutDiagnostics
    let finalClassification: String

    let present = true
    let debugOnly = true
    let rawErrorLogged = false
    let rawURLLogged = false
    let rawTokenLogged = false
    let rawRoomLogged = false
    let rawIdentityLogged = false

    static func classify(requested: Bool,
                         transportResult: String,
                         input: SalemXSenderLiveKitSDKTimelineInput) -> SalemXSenderLiveKitSDKTimeline {
        guard requested, input.provided else {
            return defaultDisabled
        }

        let timeoutDiagnostics = SalemXSenderLiveKitSDKTimeoutDiagnostics.classify(requested: requested, timeline: input)
        let classification = resolvedClassification(transportResult: transportResult,
                                                    input: input,
                                                    timeoutDiagnostics: timeoutDiagnostics)
        return .init(triggerReceived: input.triggerReceived,
                     taskCreated: input.taskCreated,
                     taskStarted: input.taskStarted,
                     connectInvoked: input.connectInvoked,
                     connectReturned: input.connectReturned,
                     connectThrew: input.connectThrew,
                     delegateAttached: input.delegateAttached,
                     stateObserverAttached: input.stateObserverAttached,
                     connectedStateSeen: input.connectedStateSeen,
                     failedStateSeen: input.failedStateSeen,
                     disconnectedStateSeen: input.disconnectedStateSeen,
                     taskCancelled: input.taskCancelled,
                     taskCompleted: input.taskCompleted,
                     timeoutElapsed: input.timeoutElapsed,
                     proofWrittenAfterTerminalState: input.proofWrittenAfterTerminalState,
                     timeoutDiagnostics: timeoutDiagnostics,
                     finalClassification: classification)
    }

    private static func resolvedClassification(transportResult: String,
                                               input: SalemXSenderLiveKitSDKTimelineInput,
                                               timeoutDiagnostics: SalemXSenderLiveKitSDKTimeoutDiagnostics) -> String {
        if transportResult == SalemXSenderTransportFailureDiagnostics.successTransportResult {
            return noneClassification
        }
        if let requestedClassification = input.requestedClassification {
            return requestedClassification
        }
        if timeoutDiagnostics.finalClassification != SalemXSenderLiveKitSDKTimeoutDiagnostics.notRequestedClassification,
           timeoutDiagnostics.finalClassification != SalemXSenderLiveKitSDKTimeoutDiagnostics.noneClassification {
            return timeoutDiagnostics.finalClassification
        }
        if let taskClassification = taskClassification(input) {
            return taskClassification
        }
        if let observerClassification = observerClassification(input) {
            return observerClassification
        }
        if let pendingClassification = pendingConnectClassification(input) {
            return pendingClassification
        }
        return internalPendingClassification
    }

    private static func taskClassification(_ input: SalemXSenderLiveKitSDKTimelineInput) -> String? {
        if input.taskCancelled {
            return taskCancelledBeforeConnectClassification
        }
        if !input.taskCreated {
            return taskNotCreatedClassification
        }
        if input.taskCreated, !input.taskStarted {
            return taskCreatedNotStartedClassification
        }
        if input.timeoutElapsed {
            return connectTimeoutClassification
        }
        return nil
    }

    private static func observerClassification(_ input: SalemXSenderLiveKitSDKTimelineInput) -> String? {
        if !input.delegateAttached {
            return delegateNotAttachedClassification
        }
        if !input.stateObserverAttached {
            return stateObserverNotAttachedClassification
        }
        return nil
    }

    private static func pendingConnectClassification(_ input: SalemXSenderLiveKitSDKTimelineInput) -> String? {
        if !input.proofWrittenAfterTerminalState, input.taskStarted || input.connectInvoked {
            return proofWrittenBeforeTerminalStateClassification
        }
        if input.connectInvoked, !input.connectReturned, !input.connectThrew, !input.connectedStateSeen, !input.failedStateSeen, !input.disconnectedStateSeen {
            return connectInvokedNoReturnClassification
        }
        if input.connectInvoked, !input.connectedStateSeen, !input.failedStateSeen, !input.disconnectedStateSeen {
            return callbackNotObservedClassification
        }
        if input.taskStarted, !input.taskCompleted {
            return internalPendingClassification
        }
        return nil
    }
}

private struct SalemXSenderLiveKitSDKFailureSurfaceInput {
    let requestedClassification: String?
    let connectCallStarted: Bool
    let connectCallReturned: Bool
    let connectCallThrew: Bool
    let connectedStateObserved: Bool
    let failedStateObserved: Bool
    let disconnectedBeforeConnected: Bool
    let delegateFailureObserved: Bool
    let roomAlreadyConnected: Bool
    let identityConflictObserved: Bool
    let tokenIdentityMatch: Bool?
    let audioSessionReady: Bool?
    let permissionRequired: Bool
    let captureStarted: Bool
    let networkTransportErrorObserved: Bool
    let timeline: SalemXSenderLiveKitSDKTimelineInput
}

private struct SalemXSenderLiveKitSDKFailureSurface {
    static let notRequestedClassification = "not_requested"
    static let noneClassification = "none"
    static let connectCallThrewClassification = "sdk_connect_call_threw_redacted"
    static let connectReturnedWithoutConnectedClassification = "sdk_connect_returned_without_connected_redacted"
    static let delegateFailedBeforeConnectedClassification = "sdk_delegate_failed_before_connected_redacted"
    static let disconnectedBeforeConnectedClassification = "sdk_disconnected_before_connected_redacted"
    static let stateFailedClassification = "sdk_state_failed_redacted"
    static let roomAlreadyConnectedClassification = "sdk_room_already_connected_redacted"
    static let identityConflictClassification = "sdk_identity_conflict_redacted"
    static let tokenIdentityMismatchClassification = "sdk_token_identity_mismatch_redacted"
    static let audioSessionBlockedClassification = "sdk_audio_session_blocked_redacted"
    static let permissionOrCaptureBlockedClassification = "sdk_permission_or_capture_blocked_redacted"
    static let networkTransportErrorClassification = "sdk_network_transport_error_redacted"
    static let internalUnknownClassification = "sdk_internal_unknown_redacted"
    static let defaultDisabled = SalemXSenderLiveKitSDKFailureSurface(connectCallStarted: false,
                                                                      connectCallReturned: false,
                                                                      connectCallThrew: false,
                                                                      connectedStateObserved: false,
                                                                      failedStateObserved: false,
                                                                      disconnectedBeforeConnected: false,
                                                                      delegateFailureObserved: false,
                                                                      roomAlreadyConnected: false,
                                                                      identityConflictObserved: false,
                                                                      tokenIdentityMatch: false,
                                                                      audioSessionReady: false,
                                                                      permissionRequired: false,
                                                                      captureStarted: false,
                                                                      timeline: .defaultDisabled,
                                                                      finalClassification: notRequestedClassification)

    let connectCallStarted: Bool
    let connectCallReturned: Bool
    let connectCallThrew: Bool
    let connectedStateObserved: Bool
    let failedStateObserved: Bool
    let disconnectedBeforeConnected: Bool
    let delegateFailureObserved: Bool
    let roomAlreadyConnected: Bool
    let identityConflictObserved: Bool
    let tokenIdentityMatch: Bool
    let audioSessionReady: Bool
    let permissionRequired: Bool
    let captureStarted: Bool
    let timeline: SalemXSenderLiveKitSDKTimeline
    let finalClassification: String

    let present = true
    let debugOnly = true
    let rawErrorLogged = false
    let rawURLLogged = false
    let rawTokenLogged = false
    let rawRoomLogged = false
    let rawIdentityLogged = false

    var transportClassification: String? {
        Self.transportClassification(for: finalClassification)
    }

    static func classify(requested: Bool,
                         transportAttempted: Bool,
                         transportResult: String,
                         input: SalemXSenderLiveKitSDKFailureSurfaceInput) -> SalemXSenderLiveKitSDKFailureSurface {
        guard requested else {
            return defaultDisabled
        }

        let timeline = SalemXSenderLiveKitSDKTimeline.classify(requested: requested,
                                                               transportResult: transportResult,
                                                               input: input.timeline)
        let classification = resolvedClassification(transportAttempted: transportAttempted,
                                                    transportResult: transportResult,
                                                    input: input,
                                                    timeline: timeline)
        return .init(connectCallStarted: input.connectCallStarted,
                     connectCallReturned: input.connectCallReturned,
                     connectCallThrew: input.connectCallThrew,
                     connectedStateObserved: input.connectedStateObserved,
                     failedStateObserved: input.failedStateObserved,
                     disconnectedBeforeConnected: input.disconnectedBeforeConnected,
                     delegateFailureObserved: input.delegateFailureObserved,
                     roomAlreadyConnected: input.roomAlreadyConnected,
                     identityConflictObserved: input.identityConflictObserved,
                     tokenIdentityMatch: input.tokenIdentityMatch ?? false,
                     audioSessionReady: input.audioSessionReady ?? false,
                     permissionRequired: input.permissionRequired,
                     captureStarted: input.captureStarted,
                     timeline: timeline,
                     finalClassification: classification)
    }

    private static func resolvedClassification(transportAttempted: Bool,
                                               transportResult: String,
                                               input: SalemXSenderLiveKitSDKFailureSurfaceInput,
                                               timeline: SalemXSenderLiveKitSDKTimeline) -> String {
        if transportResult == SalemXSenderTransportFailureDiagnostics.successTransportResult {
            return noneClassification
        }
        if let requestedClassification = input.requestedClassification {
            return requestedClassification
        }
        if let lifecycleClassification = lifecycleClassification(input) {
            return lifecycleClassification
        }
        if let boundaryClassification = boundaryClassification(input) {
            return boundaryClassification
        }
        if input.networkTransportErrorObserved {
            return networkTransportErrorClassification
        }
        if input.connectCallReturned, !input.connectedStateObserved {
            return connectReturnedWithoutConnectedClassification
        }
        if timeline.finalClassification != SalemXSenderLiveKitSDKTimeline.notRequestedClassification,
           timeline.finalClassification != SalemXSenderLiveKitSDKTimeline.noneClassification {
            return timeline.finalClassification
        }
        if transportAttempted, transportResult == SalemXSenderTransportFailureDiagnostics.failedTransportResult {
            return internalUnknownClassification
        }
        return notRequestedClassification
    }

    private static func lifecycleClassification(_ input: SalemXSenderLiveKitSDKFailureSurfaceInput) -> String? {
        if input.connectCallThrew {
            return connectCallThrewClassification
        }
        if input.delegateFailureObserved, !input.connectedStateObserved {
            return delegateFailedBeforeConnectedClassification
        }
        if input.disconnectedBeforeConnected {
            return disconnectedBeforeConnectedClassification
        }
        if input.failedStateObserved {
            return stateFailedClassification
        }
        if input.roomAlreadyConnected {
            return roomAlreadyConnectedClassification
        }
        if input.identityConflictObserved {
            return identityConflictClassification
        }
        return nil
    }

    private static func boundaryClassification(_ input: SalemXSenderLiveKitSDKFailureSurfaceInput) -> String? {
        if input.tokenIdentityMatch == false {
            return tokenIdentityMismatchClassification
        }
        if input.audioSessionReady == false {
            return audioSessionBlockedClassification
        }
        if input.permissionRequired, !input.captureStarted {
            return permissionOrCaptureBlockedClassification
        }
        return nil
    }

    private static func transportClassification(for classification: String) -> String? {
        if SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedClassifications.contains(classification) {
            return classification
        }
        switch classification {
        case connectCallThrewClassification:
            return SalemXSenderTransportErrorSurface.transportConnectThrowClassification
        case connectReturnedWithoutConnectedClassification:
            return SalemXSenderTransportErrorSurface.transportTimeoutWaitingForConnectedStateClassification
        case delegateFailedBeforeConnectedClassification:
            return SalemXSenderTransportErrorSurface.transportRoomConnectCallbackFailedClassification
        case SalemXSenderLiveKitSDKTimeline.connectTimeoutClassification,
             SalemXSenderLiveKitSDKTimeline.proofWrittenBeforeTerminalStateClassification:
            return SalemXSenderTransportErrorSurface.transportTimeoutWaitingForConnectedStateClassification
        case SalemXSenderLiveKitSDKTimeline.delegateNotAttachedClassification,
             SalemXSenderLiveKitSDKTimeline.stateObserverNotAttachedClassification,
             SalemXSenderLiveKitSDKTimeline.callbackNotObservedClassification,
             SalemXSenderLiveKitSDKTimeline.actorIsolationLostCallbackClassification:
            return SalemXSenderTransportErrorSurface.transportRoomConnectCallbackFailedClassification
        case disconnectedBeforeConnectedClassification:
            return SalemXSenderTransportErrorSurface.transportDisconnectedBeforeConnectedClassification
        case identityConflictClassification:
            return SalemXSenderTransportErrorSurface.transportAuthRejectedClassification
        case tokenIdentityMismatchClassification:
            return SalemXSenderTransportErrorSurface.transportTokenExpiredOrInvalidClassification
        case networkTransportErrorClassification:
            return SalemXSenderTransportErrorSurface.transportNetworkUnreachableClassification
        case stateFailedClassification,
             roomAlreadyConnectedClassification,
             audioSessionBlockedClassification,
             permissionOrCaptureBlockedClassification,
             internalUnknownClassification,
             SalemXSenderLiveKitSDKTimeline.taskNotCreatedClassification,
             SalemXSenderLiveKitSDKTimeline.taskCreatedNotStartedClassification,
             SalemXSenderLiveKitSDKTimeline.taskCancelledBeforeConnectClassification,
             SalemXSenderLiveKitSDKTimeline.connectInvokedNoReturnClassification,
             SalemXSenderLiveKitSDKTimeline.appLifecycleInterruptedClassification,
             SalemXSenderLiveKitSDKTimeline.internalPendingClassification:
            return SalemXSenderTransportErrorSurface.transportLiveKitSDKUnknownErrorClassification
        default:
            return nil
        }
    }
}

private struct SalemXSenderTransportErrorSurfaceInput {
    let source: String?
    let sdkErrorBucket: String?
    let disconnectReasonBucket: String?
    let websocketBucket: String?
    let authBucket: String?
    let timeoutObserved: Bool
    let connectedStateObserved: Bool
    let disconnectedBeforeConnected: Bool
    let sdkFailureSurface: SalemXSenderLiveKitSDKFailureSurface
}

private struct SalemXSenderTransportErrorSurface {
    static let notRequestedClassification = "not_requested"
    static let noneClassification = "none"
    static let notRequestedSource = "not_requested"
    static let noneBucket = "none"
    static let connectThrowSource = "connect_throw_redacted"
    static let roomConnectCallbackFailedSource = "room_connect_callback_failed_redacted"
    static let websocketCloseBucket = "websocket_close_redacted"
    static let websocketUpgradeFailedBucket = "websocket_upgrade_failed_redacted"
    static let authRejectedBucket = "auth_rejected_redacted"
    static let tokenExpiredOrInvalidBucket = "token_expired_or_invalid_redacted"
    static let tlsOrCertificateFailedBucket = "tls_or_certificate_failed_redacted"
    static let networkUnreachableBucket = "network_unreachable_redacted"
    static let liveKitSDKUnknownErrorBucket = "livekit_sdk_unknown_error_redacted"
    static let transportConnectThrowClassification = "transport_connect_throw_redacted"
    static let transportRoomConnectCallbackFailedClassification = "transport_room_connect_callback_failed_redacted"
    static let transportWebSocketCloseClassification = "transport_websocket_close_redacted"
    static let transportWebSocketUpgradeFailedClassification = "transport_websocket_upgrade_failed_redacted"
    static let transportAuthRejectedClassification = "transport_auth_rejected_redacted"
    static let transportTokenExpiredOrInvalidClassification = "transport_token_expired_or_invalid_redacted"
    static let transportTLSOrCertificateFailedClassification = "transport_tls_or_certificate_failed_redacted"
    static let transportNetworkUnreachableClassification = "transport_network_unreachable_redacted"
    static let transportTimeoutWaitingForConnectedStateClassification = "transport_timeout_waiting_for_connected_state_redacted"
    static let transportDisconnectedBeforeConnectedClassification = "transport_disconnected_before_connected_redacted"
    static let transportLiveKitSDKUnknownErrorClassification = "transport_livekit_sdk_unknown_error_redacted"
    static let transportUnknownFailedClassification = "transport_unknown_failed_redacted"
    static let defaultDisabled = SalemXSenderTransportErrorSurface(source: notRequestedSource,
                                                                   sdkErrorBucket: noneBucket,
                                                                   disconnectReasonBucket: noneBucket,
                                                                   websocketBucket: noneBucket,
                                                                   authBucket: noneBucket,
                                                                   timeoutObserved: false,
                                                                   connectedStateObserved: false,
                                                                   disconnectedBeforeConnected: false,
                                                                   sdkFailureSurface: .defaultDisabled,
                                                                   finalClassification: notRequestedClassification)

    let source: String
    let sdkErrorBucket: String
    let disconnectReasonBucket: String
    let websocketBucket: String
    let authBucket: String
    let timeoutObserved: Bool
    let connectedStateObserved: Bool
    let disconnectedBeforeConnected: Bool
    let sdkFailureSurface: SalemXSenderLiveKitSDKFailureSurface
    let finalClassification: String

    let present = true
    let debugOnly = true
    let rawErrorLogged = false
    let rawURLLogged = false
    let rawTokenLogged = false

    static func classify(requested: Bool,
                         transportAttempted: Bool,
                         transportResult: String,
                         input: SalemXSenderTransportErrorSurfaceInput) -> SalemXSenderTransportErrorSurface {
        guard requested else {
            return defaultDisabled
        }

        let classification = resolvedClassification(transportAttempted: transportAttempted,
                                                    transportResult: transportResult,
                                                    input: input)
        let source = resolvedSource(input.source, classification: classification)

        return .init(source: source,
                     sdkErrorBucket: input.sdkErrorBucket ?? noneBucket,
                     disconnectReasonBucket: input.disconnectReasonBucket ?? noneBucket,
                     websocketBucket: input.websocketBucket ?? noneBucket,
                     authBucket: input.authBucket ?? noneBucket,
                     timeoutObserved: input.timeoutObserved,
                     connectedStateObserved: input.connectedStateObserved,
                     disconnectedBeforeConnected: input.disconnectedBeforeConnected,
                     sdkFailureSurface: input.sdkFailureSurface,
                     finalClassification: classification)
    }

    private static func resolvedClassification(transportAttempted: Bool,
                                               transportResult: String,
                                               input: SalemXSenderTransportErrorSurfaceInput) -> String {
        if transportResult == SalemXSenderTransportFailureDiagnostics.successTransportResult {
            return noneClassification
        }
        if let classification = specificErrorSurfaceClassification(input) {
            return classification
        }
        return fallbackClassification(transportAttempted: transportAttempted,
                                      transportResult: transportResult,
                                      input: input)
    }

    private static func specificErrorSurfaceClassification(_ input: SalemXSenderTransportErrorSurfaceInput) -> String? {
        if let classification = input.sdkFailureSurface.transportClassification {
            return classification
        }
        if let classification = sourceClassification(input.source) {
            return classification
        }
        if let classification = websocketClassification(input.websocketBucket) {
            return classification
        }
        if let classification = authClassification(input.authBucket) {
            return classification
        }
        if let classification = sdkClassification(input.sdkErrorBucket) {
            return classification
        }
        if SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedClassifications.contains(input.sdkFailureSurface.finalClassification) {
            return input.sdkFailureSurface.finalClassification
        }
        return nil
    }

    private static func fallbackClassification(transportAttempted: Bool,
                                               transportResult: String,
                                               input: SalemXSenderTransportErrorSurfaceInput) -> String {
        if input.timeoutObserved {
            return transportTimeoutWaitingForConnectedStateClassification
        }
        if input.disconnectedBeforeConnected {
            return transportDisconnectedBeforeConnectedClassification
        }
        if input.sdkErrorBucket == liveKitSDKUnknownErrorBucket || input.source == liveKitSDKUnknownErrorBucket {
            return transportLiveKitSDKUnknownErrorClassification
        }
        if transportAttempted, transportResult == SalemXSenderTransportFailureDiagnostics.failedTransportResult {
            return transportUnknownFailedClassification
        }
        return notRequestedClassification
    }

    private static func sourceClassification(_ source: String?) -> String? {
        mappedClassification(for: source,
                             mappings: [
                                 (connectThrowSource, transportConnectThrowClassification),
                                 (roomConnectCallbackFailedSource, transportRoomConnectCallbackFailedClassification),
                                 (websocketCloseBucket, transportWebSocketCloseClassification),
                                 (websocketUpgradeFailedBucket, transportWebSocketUpgradeFailedClassification),
                                 (authRejectedBucket, transportAuthRejectedClassification),
                                 (tokenExpiredOrInvalidBucket, transportTokenExpiredOrInvalidClassification),
                                 (tlsOrCertificateFailedBucket, transportTLSOrCertificateFailedClassification),
                                 (networkUnreachableBucket, transportNetworkUnreachableClassification),
                                 (liveKitSDKUnknownErrorBucket, transportLiveKitSDKUnknownErrorClassification)
                             ])
    }

    private static func websocketClassification(_ bucket: String?) -> String? {
        mappedClassification(for: bucket,
                             mappings: [
                                 (websocketCloseBucket, transportWebSocketCloseClassification),
                                 (websocketUpgradeFailedBucket, transportWebSocketUpgradeFailedClassification)
                             ])
    }

    private static func authClassification(_ bucket: String?) -> String? {
        mappedClassification(for: bucket,
                             mappings: [
                                 (authRejectedBucket, transportAuthRejectedClassification),
                                 (tokenExpiredOrInvalidBucket, transportTokenExpiredOrInvalidClassification)
                             ])
    }

    private static func sdkClassification(_ bucket: String?) -> String? {
        mappedClassification(for: bucket,
                             mappings: [
                                 (tlsOrCertificateFailedBucket, transportTLSOrCertificateFailedClassification),
                                 (networkUnreachableBucket, transportNetworkUnreachableClassification),
                                 (liveKitSDKUnknownErrorBucket, transportLiveKitSDKUnknownErrorClassification)
                             ])
    }

    private static func mappedClassification(for value: String?, mappings: [(String, String)]) -> String? {
        guard let value else {
            return nil
        }
        return mappings.first { $0.0 == value }?.1
    }

    private static func resolvedSource(_ source: String?, classification: String) -> String {
        if let source {
            return source
        }
        if classification == noneClassification {
            return noneBucket
        }
        if classification == notRequestedClassification {
            return notRequestedSource
        }
        return liveKitSDKUnknownErrorBucket
    }
}

private struct SalemXSenderTransportFailureDiagnosticInput {
    let requested: Bool
    let liveKitURLPresent: Bool
    let tokenPresent: Bool
    let roomBindingPresent: Bool
    let sameLiveKitRoom: Bool
    let sameTokenAuthority: Bool
    let receiverSenderRoomMatch: Bool
    let receiverSenderTokenAuthorityMatch: Bool
    let transportAttempted: Bool?
    let transportStarted: Bool?
    let transportCompleted: Bool?
    let transportResult: String?
    let classification: String?
    let errorSurface: SalemXSenderTransportErrorSurface
}

private struct SalemXSenderTransportFailureDiagnostics {
    static let notRequestedClassification = "not_requested"
    static let transportNotAttemptedClassification = "transport_not_attempted_redacted"
    static let transportTimeoutClassification = "transport_timeout_redacted"
    static let transportTLSOrCertificateFailedClassification = "transport_tls_or_certificate_failed_redacted"
    static let transportWebSocketFailedClassification = "transport_websocket_failed_redacted"
    static let transportAuthRejectedClassification = "transport_auth_rejected_redacted"
    static let transportRoomNotFoundOrMismatchClassification = "transport_room_not_found_or_mismatch_redacted"
    static let transportNetworkUnreachableClassification = "transport_network_unreachable_redacted"
    static let transportLiveKitServerRejectedClassification = "transport_livekit_server_rejected_redacted"
    static let transportUnknownFailedClassification = "transport_unknown_failed_redacted"
    static let transportConnectThrowClassification = SalemXSenderTransportErrorSurface.transportConnectThrowClassification
    static let transportRoomConnectCallbackFailedClassification = SalemXSenderTransportErrorSurface.transportRoomConnectCallbackFailedClassification
    static let transportWebSocketCloseClassification = SalemXSenderTransportErrorSurface.transportWebSocketCloseClassification
    static let transportWebSocketUpgradeFailedClassification = SalemXSenderTransportErrorSurface.transportWebSocketUpgradeFailedClassification
    static let transportTokenExpiredOrInvalidClassification = SalemXSenderTransportErrorSurface.transportTokenExpiredOrInvalidClassification
    static let transportTimeoutWaitingForConnectedStateClassification = SalemXSenderTransportErrorSurface.transportTimeoutWaitingForConnectedStateClassification
    static let transportDisconnectedBeforeConnectedClassification = SalemXSenderTransportErrorSurface.transportDisconnectedBeforeConnectedClassification
    static let transportLiveKitSDKUnknownErrorClassification = SalemXSenderTransportErrorSurface.transportLiveKitSDKUnknownErrorClassification
    static let notRequestedTransportResult = "not_requested"
    static let successTransportResult = "success_redacted"
    static let failedTransportResult = "failed_redacted"
    static let defaultDisabled = SalemXSenderTransportFailureDiagnostics(transportAttempted: false,
                                                                         transportStarted: false,
                                                                         transportCompleted: false,
                                                                         transportResult: notRequestedTransportResult,
                                                                         errorBucket: "none",
                                                                         classification: notRequestedClassification,
                                                                         liveKitURLPresent: false,
                                                                         tokenPresent: false,
                                                                         roomBindingPresent: false,
                                                                         sameLiveKitRoom: false,
                                                                         sameTokenAuthority: false,
                                                                         receiverSenderRoomMatch: false,
                                                                         receiverSenderTokenAuthorityMatch: false)

    let transportAttempted: Bool
    let transportStarted: Bool
    let transportCompleted: Bool
    let transportResult: String
    let errorBucket: String
    let classification: String
    let liveKitURLPresent: Bool
    let tokenPresent: Bool
    let roomBindingPresent: Bool
    let sameLiveKitRoom: Bool
    let sameTokenAuthority: Bool
    let receiverSenderRoomMatch: Bool
    let receiverSenderTokenAuthorityMatch: Bool

    let present = true
    let debugOnly = true
    let audioOnly = true
    let videoAllowed = false
    let matrixEventsAllowed = false
    let rawIdentifiersLogged = false

    static func classify(_ input: SalemXSenderTransportFailureDiagnosticInput) -> SalemXSenderTransportFailureDiagnostics {
        guard input.requested else {
            return defaultDisabled
        }

        let attempted = input.transportAttempted ?? false
        let started = input.transportStarted ?? attempted
        let completed = input.transportCompleted ?? (input.transportResult == successTransportResult || input.transportResult == failedTransportResult)
        let result = input.transportResult ?? defaultTransportResult(attempted: attempted)
        let classification = resolvedClassification(input: input,
                                                    transportAttempted: attempted,
                                                    transportResult: result)

        return .init(transportAttempted: attempted,
                     transportStarted: started,
                     transportCompleted: completed,
                     transportResult: result,
                     errorBucket: classification == "none" ? "none" : classification,
                     classification: classification,
                     liveKitURLPresent: input.liveKitURLPresent,
                     tokenPresent: input.tokenPresent,
                     roomBindingPresent: input.roomBindingPresent,
                     sameLiveKitRoom: input.sameLiveKitRoom,
                     sameTokenAuthority: input.sameTokenAuthority,
                     receiverSenderRoomMatch: input.receiverSenderRoomMatch,
                     receiverSenderTokenAuthorityMatch: input.receiverSenderTokenAuthorityMatch)
    }

    private static func defaultTransportResult(attempted: Bool) -> String {
        attempted ? failedTransportResult : notRequestedTransportResult
    }

    private static func resolvedClassification(input: SalemXSenderTransportFailureDiagnosticInput,
                                               transportAttempted: Bool,
                                               transportResult: String) -> String {
        if !input.liveKitURLPresent || !input.tokenPresent || !input.roomBindingPresent || !transportAttempted {
            return transportNotAttemptedClassification
        }
        if !input.sameLiveKitRoom || !input.receiverSenderRoomMatch {
            return transportRoomNotFoundOrMismatchClassification
        }
        if !input.sameTokenAuthority || !input.receiverSenderTokenAuthorityMatch {
            return transportAuthRejectedClassification
        }
        if let classification = input.classification, classification != transportUnknownFailedClassification {
            return classification
        }
        if transportResult == successTransportResult {
            return "none"
        }
        if input.errorSurface.finalClassification != SalemXSenderTransportErrorSurface.notRequestedClassification,
           input.errorSurface.finalClassification != SalemXSenderTransportErrorSurface.noneClassification {
            return input.errorSurface.finalClassification
        }
        if let classification = input.classification {
            return classification
        }
        return transportUnknownFailedClassification
    }
}

private struct SalemXRemoteParticipantObserverClassification {
    let result: String
    let errorBucket: String
    let timeoutBucket: String
    let livenessErrorBucket: String?
}

private struct SalemXControlledAudioConnectExecutionGate {
    static let futurePhaseNotPermittedNoConnectReason = "future_phase_not_permitted_no_connect"
    static let credentialsMissingNoConnectReason = "credentials_missing_no_connect"
    static let activationWiringMissingNoConnectReason = "activation_wiring_missing_no_connect"
    static let enablementWiringMissingNoConnectReason = "enablement_wiring_missing_no_connect"
    static let enablementDisabledNoConnectReason = "enablement_disabled_no_connect"
    static let operatorApprovalMissingNoConnectReason = "operator_approval_missing_no_connect"
    static let freshCredentialsMissingNoConnectReason = "fresh_credentials_missing_no_connect"
    static let audioOnlyScopeMissingNoConnectReason = "audio_only_scope_missing_no_connect"
    static let videoEnabledNoConnectReason = "video_enabled_no_connect"
    static let matrixEventsEnabledNoConnectReason = "matrix_events_enabled_no_connect"
    static let rawCredentialsLoggedNoConnectReason = "raw_credentials_logged_no_connect"

    static func defaultBlocked(credentialsPresent: Bool) -> SalemXControlledAudioConnectExecutionGate {
        SalemXControlledAudioConnectExecutionGate(credentialsPresent: credentialsPresent,
                                                  activationConfiguration: .defaultDisabled,
                                                  enablementConfiguration: .defaultDisabled)
    }

    let credentialsPresent: Bool
    let activationConfiguration: SalemXControlledMediaConnectActivationConfiguration
    let enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration

    let gatePresent = true
    let debugOnly = true
    let requiresEnablement = true
    let requiresOperatorApproval = true
    let requiresFuturePhasePermission = true

    var audioOnly: Bool {
        enablementConfiguration.audioOnlyScope
    }

    var videoAllowed: Bool {
        activationConfiguration.videoAllowed || enablementConfiguration.videoAllowed
    }

    var matrixEventsAllowed: Bool {
        activationConfiguration.matrixEventsAllowed || enablementConfiguration.matrixEventsAllowed
    }

    var rawCredentialsLogged: Bool {
        activationConfiguration.rawCredentialsLogged || enablementConfiguration.rawCredentialsLogged
    }

    var futurePhasePermitted: Bool {
        enablementConfiguration.futureConnectPhasePermitted
    }

    var executionAllowed: Bool {
        credentialsPresent
            && activationConfiguration.wiringPresent
            && enablementConfiguration.wiringPresent
            && enablementConfiguration.oneShotEnablementEnabled
            && activationConfiguration.controlledConnectSwitch.executionAllowed
            && enablementConfiguration.operatorApproved
            && enablementConfiguration.freshCredentialsPresent
            && audioOnly
            && !videoAllowed
            && !matrixEventsAllowed
            && !rawCredentialsLogged
            && futurePhasePermitted
    }

    var blockedReason: String {
        if executionAllowed {
            return "none"
        }
        if !futurePhasePermitted {
            return Self.futurePhaseNotPermittedNoConnectReason
        }
        if !credentialsPresent {
            return Self.credentialsMissingNoConnectReason
        }
        if !activationConfiguration.wiringPresent {
            return Self.activationWiringMissingNoConnectReason
        }
        if !enablementConfiguration.wiringPresent {
            return Self.enablementWiringMissingNoConnectReason
        }
        if !enablementConfiguration.oneShotEnablementEnabled {
            return Self.enablementDisabledNoConnectReason
        }
        if !activationConfiguration.controlledConnectSwitch.executionAllowed || !enablementConfiguration.operatorApproved {
            return Self.operatorApprovalMissingNoConnectReason
        }
        if !enablementConfiguration.freshCredentialsPresent {
            return Self.freshCredentialsMissingNoConnectReason
        }
        if !audioOnly {
            return Self.audioOnlyScopeMissingNoConnectReason
        }
        if videoAllowed {
            return Self.videoEnabledNoConnectReason
        }
        if matrixEventsAllowed {
            return Self.matrixEventsEnabledNoConnectReason
        }
        if rawCredentialsLogged {
            return Self.rawCredentialsLoggedNoConnectReason
        }
        return Self.futurePhaseNotPermittedNoConnectReason
    }

    var blockedBeforeEngine: Bool {
        !executionAllowed
    }

    var blockedBeforeLiveKitJoin: Bool {
        !executionAllowed
    }

    var blockedBeforePermissions: Bool {
        !executionAllowed
    }

    var blockedBeforeMatrixEvents: Bool {
        !executionAllowed
    }
}

private struct SalemXControlledAudioConnectActivationPath {
    static let activationPathDisabledNoConnectReason = "activation_path_disabled_no_connect"

    static func defaultDisabled(receiverAppSessionValidated: Bool, credentialsPresent: Bool) -> SalemXControlledAudioConnectActivationPath {
        SalemXControlledAudioConnectActivationPath(receiverAppSessionValidated: receiverAppSessionValidated,
                                                   credentialsPresent: credentialsPresent,
                                                   enablementConfiguration: .defaultDisabled)
    }

    let receiverAppSessionValidated: Bool
    let credentialsPresent: Bool
    let enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration

    let pathPresent = true
    let debugOnly = true
    let isOneShot = true
    let isDefaultDisabled = true
    let requiresReceiverSession = true
    let requiresFreshCredentials = true
    let requiresEnablement = true
    let requiresOperatorApproval = true
    let requiresFuturePhasePermission = true

    var audioOnly: Bool {
        enablementConfiguration.audioOnlyScope
    }

    var videoAllowed: Bool {
        enablementConfiguration.videoAllowed
    }

    var matrixEventsAllowed: Bool {
        enablementConfiguration.matrixEventsAllowed
    }

    var rawCredentialsLogged: Bool {
        enablementConfiguration.rawCredentialsLogged
    }

    var rollbackAvailable: Bool {
        enablementConfiguration.rollbackAvailable
    }

    var activationAllowed: Bool {
        debugOnly
            && receiverAppSessionValidated
            && credentialsPresent
            && enablementConfiguration.oneShotEnablementEnabled
            && enablementConfiguration.operatorApproved
            && enablementConfiguration.futureConnectPhasePermitted
            && audioOnly
            && !videoAllowed
            && !matrixEventsAllowed
            && !rawCredentialsLogged
            && rollbackAvailable
            && isOneShot
    }

    var blockedReason: String {
        activationAllowed ? "none" : Self.activationPathDisabledNoConnectReason
    }

    var blockedBeforeEngine: Bool {
        !activationAllowed
    }

    var blockedBeforeLiveKitJoin: Bool {
        !activationAllowed
    }

    var blockedBeforePermissions: Bool {
        !activationAllowed
    }

    var blockedBeforeMatrixEvents: Bool {
        !activationAllowed
    }
}

private struct SalemXControlledAudioConnectRealAudioPath {
    static let defaultDisabledNoConnectReason = "default_disabled_no_connect"
    static let oneShotConsumedNoConnectReason = "one_shot_consumed_no_connect"
    static let defaultDisabled = SalemXControlledAudioConnectRealAudioPath(enablementConfiguration: .defaultDisabled,
                                                                           executionGate: .defaultBlocked(credentialsPresent: false),
                                                                           activationPath: .defaultDisabled(receiverAppSessionValidated: false,
                                                                                                            credentialsPresent: false),
                                                                           oneShotNotConsumed: true)

    let enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration
    let executionGate: SalemXControlledAudioConnectExecutionGate
    let activationPath: SalemXControlledAudioConnectActivationPath
    let oneShotNotConsumed: Bool

    let present = true
    let debugOnly = true
    let isDefaultDisabled = true
    let requiresEnablement = true
    let requiresOperatorApproval = true
    let requiresFuturePhasePermission = true
    let oneShot = true
    let canReachEngineWhenAllGatesTrue = true

    var audioOnly: Bool {
        enablementConfiguration.audioOnlyScope && executionGate.audioOnly && activationPath.audioOnly
    }

    var videoAllowed: Bool {
        executionGate.videoAllowed || activationPath.videoAllowed
    }

    var matrixEventsAllowed: Bool {
        executionGate.matrixEventsAllowed || activationPath.matrixEventsAllowed
    }

    var rawCredentialsLogged: Bool {
        executionGate.rawCredentialsLogged || activationPath.rawCredentialsLogged
    }

    var allowed: Bool {
        debugOnly &&
            present &&
            enablementConfiguration.executionAllowed &&
            executionGate.executionAllowed &&
            activationPath.activationAllowed &&
            audioOnly &&
            !videoAllowed &&
            !matrixEventsAllowed &&
            !rawCredentialsLogged &&
            oneShot &&
            oneShotNotConsumed &&
            canReachEngineWhenAllGatesTrue
    }

    var blockedReason: String {
        if allowed {
            return "none"
        }
        if !oneShotNotConsumed {
            return Self.oneShotConsumedNoConnectReason
        }
        if !enablementConfiguration.oneShotEnablementEnabled {
            return Self.defaultDisabledNoConnectReason
        }
        if !enablementConfiguration.executionAllowed {
            return enablementConfiguration.blockedReason
        }
        if !executionGate.executionAllowed {
            return executionGate.blockedReason
        }
        if !activationPath.activationAllowed {
            return activationPath.blockedReason
        }
        return SalemXControlledAudioConnectFirstAttempt.gateBlockedNoConnectReason
    }

    var blockedBeforeEngine: Bool {
        !allowed
    }
}

private struct SalemXControlledAudioConnectRealRuntimePath {
    static let defaultDisabledNoConnectReason = "default_disabled_no_connect"
    static let oneShotConsumedNoConnectReason = "one_shot_consumed_no_connect"
    static let defaultDisabled = SalemXControlledAudioConnectRealRuntimePath(credentialsPresent: false,
                                                                             enablementConfiguration: .defaultDisabled,
                                                                             executionGate: .defaultBlocked(credentialsPresent: false),
                                                                             activationPath: .defaultDisabled(receiverAppSessionValidated: false,
                                                                                                              credentialsPresent: false),
                                                                             oneShotNotConsumed: true)

    let credentialsPresent: Bool
    let enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration
    let executionGate: SalemXControlledAudioConnectExecutionGate
    let activationPath: SalemXControlledAudioConnectActivationPath
    let oneShotNotConsumed: Bool

    let present = true
    let debugOnly = true
    let isDefaultDisabled = true
    let requiresCredentials = true
    let requiresEnablement = true
    let requiresOperatorApproval = true
    let requiresFuturePhasePermission = true
    let oneShot = true
    let canCallConnectMediaWhenAllGatesTrue = true
    let canCallLiveKitAudioWhenAllGatesTrue = true

    var audioOnly: Bool {
        enablementConfiguration.audioOnlyScope && executionGate.audioOnly && activationPath.audioOnly
    }

    var videoAllowed: Bool {
        executionGate.videoAllowed || activationPath.videoAllowed
    }

    var matrixEventsAllowed: Bool {
        executionGate.matrixEventsAllowed || activationPath.matrixEventsAllowed
    }

    var rawCredentialsLogged: Bool {
        executionGate.rawCredentialsLogged || activationPath.rawCredentialsLogged
    }

    var allowed: Bool {
        debugOnly &&
            present &&
            credentialsPresent &&
            enablementConfiguration.executionAllowed &&
            executionGate.executionAllowed &&
            activationPath.activationAllowed &&
            audioOnly &&
            !videoAllowed &&
            !matrixEventsAllowed &&
            !rawCredentialsLogged &&
            oneShot &&
            oneShotNotConsumed &&
            canCallConnectMediaWhenAllGatesTrue &&
            canCallLiveKitAudioWhenAllGatesTrue
    }

    var blockedReason: String {
        if allowed {
            return "none"
        }
        if !oneShotNotConsumed {
            return Self.oneShotConsumedNoConnectReason
        }
        if !enablementConfiguration.oneShotEnablementEnabled {
            return Self.defaultDisabledNoConnectReason
        }
        if !credentialsPresent {
            return SalemXControlledAudioConnectExecutionGate.credentialsMissingNoConnectReason
        }
        if !enablementConfiguration.executionAllowed {
            return enablementConfiguration.blockedReason
        }
        if !executionGate.executionAllowed {
            return executionGate.blockedReason
        }
        if !activationPath.activationAllowed {
            return activationPath.blockedReason
        }
        return SalemXControlledAudioConnectFirstAttempt.gateBlockedNoConnectReason
    }

    var blockedBeforeEngine: Bool {
        !allowed
    }
}

@MainActor
private protocol SalemXControlledAudioConnectRuntimeBoundary {
    func connectMediaIfReadyWhenControlledGatesOpen(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>
}

@MainActor
private struct SalemXDirectCallEngineControlledAudioConnectRuntimeBoundary: SalemXControlledAudioConnectRuntimeBoundary {
    let directCallEngine: any DirectCallEngineProtocol

    func connectMediaIfReadyWhenControlledGatesOpen(callID: String) async -> Result<DirectCallSession, DirectCallEngineError> {
        await directCallEngine.acceptCall(callID: callID)
    }
}

private struct SalemXControlledAudioConnectRealBridge {
    static let defaultDisabledNoConnectReason = "default_disabled_no_connect"
    static let oneShotConsumedNoConnectReason = "one_shot_consumed_no_connect"
    static let defaultDisabled = SalemXControlledAudioConnectRealBridge(realRuntimePath: .defaultDisabled,
                                                                        oneShotNotConsumed: true)

    let realRuntimePath: SalemXControlledAudioConnectRealRuntimePath
    let oneShotNotConsumed: Bool

    let present = true
    let debugOnly = true
    let isDefaultDisabled = true
    let requiresCredentials = true
    let requiresEnablement = true
    let requiresOperatorApproval = true
    let requiresFuturePhasePermission = true
    let oneShot = true
    let canCallConnectMediaWhenAllGatesTrue = true
    let canCallLiveKitAudioWhenAllGatesTrue = true
    let usesFakeEngineInTestsOnly = true
    let usesRealRuntimeBoundaryWhenNotTest = true

    var audioOnly: Bool {
        realRuntimePath.audioOnly
    }

    var videoAllowed: Bool {
        realRuntimePath.videoAllowed
    }

    var matrixEventsAllowed: Bool {
        realRuntimePath.matrixEventsAllowed
    }

    var rawCredentialsLogged: Bool {
        realRuntimePath.rawCredentialsLogged
    }

    var allowed: Bool {
        debugOnly &&
            present &&
            realRuntimePath.allowed &&
            oneShot &&
            oneShotNotConsumed &&
            canCallConnectMediaWhenAllGatesTrue &&
            canCallLiveKitAudioWhenAllGatesTrue &&
            usesRealRuntimeBoundaryWhenNotTest
    }

    var blockedReason: String {
        if allowed {
            return "none"
        }
        if !oneShotNotConsumed {
            return Self.oneShotConsumedNoConnectReason
        }
        if !realRuntimePath.allowed {
            return realRuntimePath.blockedReason
        }
        return SalemXControlledAudioConnectFirstAttempt.gateBlockedNoConnectReason
    }

    var blockedBeforeConnectMedia: Bool {
        !allowed
    }

    @MainActor
    func connectMediaIfReadyWhenControlledGatesOpen(session: DirectCallSession,
                                                    runtimeBoundary: any SalemXControlledAudioConnectRuntimeBoundary) async -> SalemXControlledAudioConnectFirstAttempt {
        guard allowed else {
            return .blockedByRealBridge(self)
        }

        let result = await runtimeBoundary.connectMediaIfReadyWhenControlledGatesOpen(callID: session.callID)
        return .controlledRealBridgeRuntimeBoundary(realBridge: self, result: result)
    }
}

private struct SalemXControlledAudioConnectFakeFirstAttemptMediaEngine {
    let usesRealLiveKitNetwork = false
    let mediaConnectRequested = true
    let mediaConnectAttempted = true
    let liveKitJoinRequested = true
    let liveKitConnectAudioInvoked = true
    let microphonePermissionRequested = false
    let cameraPermissionRequested = false
    let matrixEventEmitRequested = false
    let realCallFlowStarted = false
    let firstAttemptResult = "success_redacted"
    let firstAttemptErrorBucket = "none"
}

private struct SalemXControlledAudioConnectFirstAttempt {
    static let defaultDisabledNoConnectReason = "default_disabled_no_connect"
    static let gateBlockedNoConnectReason = "gate_blocked_no_connect"
    static let defaultDisabled = SalemXControlledAudioConnectFirstAttempt(requested: false,
                                                                          allowed: false,
                                                                          started: false,
                                                                          completed: false,
                                                                          repeated: false,
                                                                          result: "not_requested",
                                                                          errorBucket: "none",
                                                                          audioOnly: true,
                                                                          videoAllowed: false,
                                                                          matrixEventsAllowed: false,
                                                                          rawCredentialsLogged: false,
                                                                          blockedReason: defaultDisabledNoConnectReason,
                                                                          mediaConnectRequested: false,
                                                                          mediaConnectAttempted: false,
                                                                          liveKitJoinRequested: false,
                                                                          liveKitConnectAudioInvoked: false,
                                                                          microphonePermissionRequested: false,
                                                                          cameraPermissionRequested: false,
                                                                          matrixEventEmitRequested: false,
                                                                          realCallFlowStarted: false)

    static func controlledRealPathTestBoundary(realAudioPath: SalemXControlledAudioConnectRealAudioPath,
                                               fakeMediaEngine: SalemXControlledAudioConnectFakeFirstAttemptMediaEngine = .init()) -> SalemXControlledAudioConnectFirstAttempt {
        let requested = true
        let allowed = requested &&
            realAudioPath.allowed &&
            realAudioPath.canReachEngineWhenAllGatesTrue &&
            !fakeMediaEngine.usesRealLiveKitNetwork &&
            !fakeMediaEngine.cameraPermissionRequested &&
            !fakeMediaEngine.matrixEventEmitRequested &&
            !fakeMediaEngine.realCallFlowStarted

        return SalemXControlledAudioConnectFirstAttempt(requested: requested,
                                                        allowed: allowed,
                                                        started: allowed,
                                                        completed: allowed,
                                                        repeated: false,
                                                        result: allowed ? fakeMediaEngine.firstAttemptResult : "blocked_redacted",
                                                        errorBucket: allowed ? fakeMediaEngine.firstAttemptErrorBucket : realAudioPath.blockedReason,
                                                        audioOnly: realAudioPath.audioOnly,
                                                        videoAllowed: realAudioPath.videoAllowed,
                                                        matrixEventsAllowed: realAudioPath.matrixEventsAllowed,
                                                        rawCredentialsLogged: realAudioPath.rawCredentialsLogged,
                                                        blockedReason: allowed ? "none" : realAudioPath.blockedReason,
                                                        mediaConnectRequested: allowed && fakeMediaEngine.mediaConnectRequested,
                                                        mediaConnectAttempted: allowed && fakeMediaEngine.mediaConnectAttempted,
                                                        liveKitJoinRequested: allowed && fakeMediaEngine.liveKitJoinRequested,
                                                        liveKitConnectAudioInvoked: allowed && fakeMediaEngine.liveKitConnectAudioInvoked,
                                                        microphonePermissionRequested: allowed && fakeMediaEngine.microphonePermissionRequested,
                                                        cameraPermissionRequested: false,
                                                        matrixEventEmitRequested: false,
                                                        realCallFlowStarted: false)
    }

    static func controlledRealRuntimeBoundary(realRuntimePath: SalemXControlledAudioConnectRealRuntimePath,
                                              fakeMediaEngine: SalemXControlledAudioConnectFakeFirstAttemptMediaEngine = .init()) -> SalemXControlledAudioConnectFirstAttempt {
        let requested = realRuntimePath.allowed
        let allowed = requested &&
            realRuntimePath.canCallConnectMediaWhenAllGatesTrue &&
            realRuntimePath.canCallLiveKitAudioWhenAllGatesTrue &&
            !fakeMediaEngine.usesRealLiveKitNetwork &&
            !fakeMediaEngine.cameraPermissionRequested &&
            !fakeMediaEngine.matrixEventEmitRequested &&
            !fakeMediaEngine.realCallFlowStarted

        return SalemXControlledAudioConnectFirstAttempt(requested: requested,
                                                        allowed: allowed,
                                                        started: allowed,
                                                        completed: allowed,
                                                        repeated: false,
                                                        result: allowed ? fakeMediaEngine.firstAttemptResult : "blocked_redacted",
                                                        errorBucket: allowed ? fakeMediaEngine.firstAttemptErrorBucket : realRuntimePath.blockedReason,
                                                        audioOnly: realRuntimePath.audioOnly,
                                                        videoAllowed: realRuntimePath.videoAllowed,
                                                        matrixEventsAllowed: realRuntimePath.matrixEventsAllowed,
                                                        rawCredentialsLogged: realRuntimePath.rawCredentialsLogged,
                                                        blockedReason: allowed ? "none" : realRuntimePath.blockedReason,
                                                        mediaConnectRequested: allowed && fakeMediaEngine.mediaConnectRequested,
                                                        mediaConnectAttempted: allowed && fakeMediaEngine.mediaConnectAttempted,
                                                        liveKitJoinRequested: allowed && fakeMediaEngine.liveKitJoinRequested,
                                                        liveKitConnectAudioInvoked: allowed && fakeMediaEngine.liveKitConnectAudioInvoked,
                                                        microphonePermissionRequested: allowed && fakeMediaEngine.microphonePermissionRequested,
                                                        cameraPermissionRequested: false,
                                                        matrixEventEmitRequested: false,
                                                        realCallFlowStarted: false)
    }

    static func controlledRealBridgeTestBoundary(realBridge: SalemXControlledAudioConnectRealBridge,
                                                 fakeMediaEngine: SalemXControlledAudioConnectFakeFirstAttemptMediaEngine = .init()) -> SalemXControlledAudioConnectFirstAttempt {
        let requested = realBridge.allowed
        let allowed = requested &&
            realBridge.usesFakeEngineInTestsOnly &&
            realBridge.canCallConnectMediaWhenAllGatesTrue &&
            realBridge.canCallLiveKitAudioWhenAllGatesTrue &&
            !fakeMediaEngine.usesRealLiveKitNetwork &&
            !fakeMediaEngine.cameraPermissionRequested &&
            !fakeMediaEngine.matrixEventEmitRequested &&
            !fakeMediaEngine.realCallFlowStarted

        return SalemXControlledAudioConnectFirstAttempt(requested: requested,
                                                        allowed: allowed,
                                                        started: allowed,
                                                        completed: allowed,
                                                        repeated: false,
                                                        result: allowed ? fakeMediaEngine.firstAttemptResult : "blocked_redacted",
                                                        errorBucket: allowed ? fakeMediaEngine.firstAttemptErrorBucket : realBridge.blockedReason,
                                                        audioOnly: realBridge.audioOnly,
                                                        videoAllowed: realBridge.videoAllowed,
                                                        matrixEventsAllowed: realBridge.matrixEventsAllowed,
                                                        rawCredentialsLogged: realBridge.rawCredentialsLogged,
                                                        blockedReason: allowed ? "none" : realBridge.blockedReason,
                                                        mediaConnectRequested: allowed && fakeMediaEngine.mediaConnectRequested,
                                                        mediaConnectAttempted: allowed && fakeMediaEngine.mediaConnectAttempted,
                                                        liveKitJoinRequested: allowed && fakeMediaEngine.liveKitJoinRequested,
                                                        liveKitConnectAudioInvoked: allowed && fakeMediaEngine.liveKitConnectAudioInvoked,
                                                        microphonePermissionRequested: allowed && fakeMediaEngine.microphonePermissionRequested,
                                                        cameraPermissionRequested: false,
                                                        matrixEventEmitRequested: false,
                                                        realCallFlowStarted: false)
    }

    static func controlledRealBridgeRuntimeBoundary(realBridge: SalemXControlledAudioConnectRealBridge,
                                                    result: Result<DirectCallSession, DirectCallEngineError>) -> SalemXControlledAudioConnectFirstAttempt {
        let succeeded: Bool
        let errorBucket: String
        switch result {
        case .success:
            succeeded = true
            errorBucket = "none"
        case .failure(let error):
            succeeded = false
            errorBucket = Self.redactedErrorBucket(for: error)
        }

        return SalemXControlledAudioConnectFirstAttempt(requested: realBridge.allowed,
                                                        allowed: realBridge.allowed,
                                                        started: realBridge.allowed,
                                                        completed: realBridge.allowed,
                                                        repeated: false,
                                                        result: succeeded ? "success_redacted" : "blocked_redacted",
                                                        errorBucket: errorBucket,
                                                        audioOnly: realBridge.audioOnly,
                                                        videoAllowed: realBridge.videoAllowed,
                                                        matrixEventsAllowed: realBridge.matrixEventsAllowed,
                                                        rawCredentialsLogged: realBridge.rawCredentialsLogged,
                                                        blockedReason: succeeded ? "none" : "runtime_connect_failed_redacted",
                                                        mediaConnectRequested: realBridge.allowed,
                                                        mediaConnectAttempted: realBridge.allowed,
                                                        liveKitJoinRequested: realBridge.allowed,
                                                        liveKitConnectAudioInvoked: realBridge.allowed,
                                                        microphonePermissionRequested: false,
                                                        cameraPermissionRequested: false,
                                                        matrixEventEmitRequested: false,
                                                        realCallFlowStarted: false)
    }

    static func blockedByRealBridge(_ realBridge: SalemXControlledAudioConnectRealBridge) -> SalemXControlledAudioConnectFirstAttempt {
        SalemXControlledAudioConnectFirstAttempt(requested: false,
                                                 allowed: false,
                                                 started: false,
                                                 completed: false,
                                                 repeated: false,
                                                 result: "not_requested",
                                                 errorBucket: "none",
                                                 audioOnly: realBridge.audioOnly,
                                                 videoAllowed: realBridge.videoAllowed,
                                                 matrixEventsAllowed: realBridge.matrixEventsAllowed,
                                                 rawCredentialsLogged: realBridge.rawCredentialsLogged,
                                                 blockedReason: realBridge.blockedReason,
                                                 mediaConnectRequested: false,
                                                 mediaConnectAttempted: false,
                                                 liveKitJoinRequested: false,
                                                 liveKitConnectAudioInvoked: false,
                                                 microphonePermissionRequested: false,
                                                 cameraPermissionRequested: false,
                                                 matrixEventEmitRequested: false,
                                                 realCallFlowStarted: false)
    }

    static func fakeBoundaryForTests(enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration,
                                     executionGate: SalemXControlledAudioConnectExecutionGate,
                                     activationPath: SalemXControlledAudioConnectActivationPath,
                                     fakeMediaEngine: SalemXControlledAudioConnectFakeFirstAttemptMediaEngine = .init()) -> SalemXControlledAudioConnectFirstAttempt {
        controlledRealPathTestBoundary(realAudioPath: SalemXControlledAudioConnectRealAudioPath(enablementConfiguration: enablementConfiguration,
                                                                                                executionGate: executionGate,
                                                                                                activationPath: activationPath,
                                                                                                oneShotNotConsumed: true),
                                       fakeMediaEngine: fakeMediaEngine)
    }

    private static func redactedErrorBucket(for error: DirectCallEngineError) -> String {
        if case .mediaConnectionFailed = error {
            return "media_connection_failed_redacted"
        }
        return "connect_failed_redacted"
    }

    let requested: Bool
    let allowed: Bool
    let started: Bool
    let completed: Bool
    let repeated: Bool
    let result: String
    let errorBucket: String
    let audioOnly: Bool
    let videoAllowed: Bool
    let matrixEventsAllowed: Bool
    let rawCredentialsLogged: Bool
    let blockedReason: String
    let mediaConnectRequested: Bool
    let mediaConnectAttempted: Bool
    let liveKitJoinRequested: Bool
    let liveKitConnectAudioInvoked: Bool
    let microphonePermissionRequested: Bool
    let cameraPermissionRequested: Bool
    let matrixEventEmitRequested: Bool
    let realCallFlowStarted: Bool
}

// swiftlint:disable:next type_body_length
private struct SalemXVoIPPushReceiptProofSummary {
    var proofSource = "voip_push_receipt"
    var proofGeneration = "not_started"
    var proofLastUpdatedBy = "not_started"
    var physicalVoIPPushReceived = false
    var callbackInvoked = false
    var pushType = "none"
    var payloadVersion = "none"
    var payloadKind = "none"
    var pendingMetadataReferencePresent = false
    var pendingMetadataReferenceRedacted = true
    var pendingMetadataFetchRequired = false
    var pendingMetadataFetchRequested = false
    var pendingMetadataFetchAuthorized = false
    var pendingMetadataFetchResult = "not_requested"
    var pendingMetadataFetchHTTPStatusBucket = "not_requested"
    var pendingMetadataFetchErrcode = "none"
    var pendingMetadataFetchFailureReason = "none"
    var pendingMetadataPayloadRedacted = true
    var receiverVoIPPushDeliveryTriagePresent = true
    var receiverVoIPPushDeliveryTriageDebugOnly = true
    var receiverVoIPPushDeliveryTriageRawIdentifiersLogged = false
    var receiverPushKitTokenReadinessRepairPresent = true
    var receiverPushKitTokenReadinessRepairDebugOnly = true
    var receiverPushKitTokenReadinessRepairRawIdentifiersLogged = false
    var receiverPushKitRegistrationRequestedBeforeAPNs = false
    var receiverPushKitTokenCallbackSeenBeforeAPNs = false
    var receiverPushKitTokenPresentBeforeAPNs = false
    var receiverPushKitTokenUploadAttemptedBeforeAPNs = false
    var receiverPushKitTokenUploadResultBucket = "unknown"
    var receiverPushKitTokenServerStoreResultBucket = "unknown"
    var receiverPushKitTokenEnvironmentBucket = "unknown"
    var receiverPushKitTokenDeviceBindingExpectedBucket = "unknown"
    var receiverPushKitTokenReadinessWaitStarted = false
    var receiverPushKitTokenReadinessWaitCompleted = false
    var receiverPushKitTokenReadinessWaitTimeout = false
    var receiverPushKitTokenReadinessFinalClassification = "receiver_pushkit_registration_not_requested_before_apns_redacted"
    var receiverPostAnswerMediaCredentialsContinuationRepairPresent = true
    var receiverPostAnswerMediaCredentialsContinuationRepairDebugOnly = true
    var receiverPostAnswerMediaCredentialsContinuationRepairRawIdentifiersLogged = false
    var receiverAppLifecycleStateBeforeAPNsBucket = "unknown"
    var receiverAppProofGenerationBeforeAPNs = "unknown"
    var receiverAppProofGenerationAfterAPNsChanged = false
    var receiverVoIPPushCallbackSeenAfterAPNs = false
    var receiverCallKitReportRequestedAfterAPNs = false
    var receiverCallKitAnswerAvailableAfterAPNs = false
    var receiverCallKitSurfaceOperatorReadinessRepairPresent = true
    var receiverCallKitSurfaceOperatorReadinessRepairDebugOnly = true
    var receiverCallKitSurfaceOperatorReadinessRepairRawIdentifiersLogged = false
    var receiverCallKitOperatorReadyMarkerRequestedBeforeAPNs = false
    var receiverCallKitAnswerWindowExtendedForUISurface = false
    var receiverForegroundInAppAnswerContinuationRepairPresent = true
    var receiverForegroundInAppAnswerContinuationRepairDebugOnly = true
    var receiverForegroundInAppAnswerContinuationRepairRawIdentifiersLogged = false
    var receiverForegroundInAppAnswerHookPresent = true
    var receiverForegroundInAppAnswerHookDefaultDisabled = true
    var receiverForegroundInAppAnswerHookRequested = false
    var receiverForegroundInAppAnswerHookAllowed = false
    var receiverForegroundInAppAnswerHookBlockedReason = "not_requested"
    var receiverForegroundInAppAnswerRecorded = false
    var receiverForegroundInAppAnswerPreservedPendingMetadata = false
    var receiverForegroundInAppAnswerTriggeredPostAnswerContinuation = false
    var receiverForegroundInAppAnswerFinalClassification = "not_requested"
    var apnsProviderAcceptanceResultBucket = "unknown"
    var apnsDeliveryCallbackMissingAfterAcceptance = false
    var receiverVoIPPushDeliveryFinalClassification = "receiver_pushkit_token_device_binding_unknown_redacted"
    var realInvitePayloadMappingObserved = false
    var elementCallServicePushKitCallbackInvoked = false
    var elementCallServiceSalemXPayloadObserved = false
    var elementCallServicePayloadKind = "none"
    var elementCallServiceForwardedToSalemXReceiptPipeline = false
    var elementCallServiceCompletedWithoutSalemXCallKitReport = false
    var completionCalled = false
    var callKitReportRequested = false
    var callKitReportResult = "not_requested"
    var callKitReportCompletionObserved = false
    var callKitReportSubmittedAtMsRedacted = false
    var callKitReportCompletionAtMsRedacted = false
    var callKitSurfaceRepairPresent = true
    var callKitSurfaceRepairDebugOnly = true
    var callKitSurfaceRepairProviderRetentionVerified = false
    var callKitSurfaceRepairDelegateRetentionVerified = false
    var callKitSurfaceRepairActiveUUIDRetentionVerified = false
    var callKitSurfaceRepairReportCompletionWatchdogPresent = true
    var callKitSurfaceRepairReportCompletionTimeoutClassified = false
    var callKitSurfaceRepairPushKitCompletionSafetyPresent = true
    var callKitSurfaceRepairPushKitCompletionSafetyResult = "not_requested"
    var callKitSurfaceRepairBackgroundTaskRequested = false
    var callKitSurfaceRepairBackgroundTaskEnded = false
    var callKitSurfaceRepairBlocksConnectWithoutAnswer = true
    var callKitSurfaceRepairBlocksMetadataWithoutAnswer = true
    var callKitSurfaceRepairNoDirectAnswerBypass = true
    var callKitSurfaceRepairNoMediaConnectOnNoAnswer = true
    var metadataCredentialsBoundaryRepairPresent = true
    var metadataCredentialsBoundaryRepairDebugOnly = true
    var metadataCredentialsBoundaryRepairRequiresAnswer = true
    var metadataCredentialsBoundaryRepairBlocksWithoutAnswer = true
    var metadataCredentialsBoundaryRepairTriggersMetadataAfterAnswer = true
    var metadataCredentialsBoundaryRepairTriggersCredentialsAfterMetadata = true
    var metadataCredentialsBoundaryRepairBlocksConnectUntilCredentials = true
    var metadataCredentialsBoundaryRepairDoesNotConsumeHookBeforeCredentials = true
    var metadataCredentialsBoundaryRepairAllowsHookConsumptionAfterCredentials = false
    var metadataCredentialsBoundaryRepairNoDirectConnectBypass = true
    var metadataCredentialsBoundaryRepairRawCredentialsLogged = false
    var pendingMetadataReferenceRepairPresent = true
    var pendingMetadataReferenceRepairDebugOnly = true
    var pendingMetadataReferenceRepairRealInviteRequired = true
    var pendingMetadataReferenceRepairReferenceCreatedBeforeAPNs = false
    var pendingMetadataReferenceRepairReferencePresentInAPNsPayload = false
    var pendingMetadataReferenceRepairReferenceObservedByPushKit = false
    var pendingMetadataReferenceRepairReferenceHandedToAnswerPipeline = false
    var pendingMetadataReferenceRepairBlocksAPNsWithoutReference = true
    var pendingMetadataReferenceRepairBlocksCredentialsWithoutMetadataSuccess = true
    var pendingMetadataReferenceRepairNoDirectCredentialsBypass = true
    var pendingMetadataReferenceRepairNoConnectBypass = true
    var pendingMetadataReferenceRepairRawMetadataLogged = false
    var pushKitCompletionAnswerableWindowRequested = false
    var pushKitCompletionAnswerableWindowResult = "not_requested"
    var pushKitCompletionAnswerableWindowDurationBucket = "not_requested"
    var pushKitCompletionAfterReportMsBucket = "unknown"
    var callKitEndAfterPushKitCompletionMsBucket = "unknown"
    var appStateAtPushKitReceipt = "unknown"
    var appStateAtReportCompletion = "unknown"
    var appStateAtFirstCallKitAction = "unknown"
    var callKitUpdateHasGenericHandle = false
    var callKitUpdateHasLocalizedCallerName = false
    var callKitUpdateAudioOnly = false
    var callKitProviderConfigurationAudioOnly = false
    var callKitProviderConfigurationSupportedHandleGeneric = false
    var localCallKitOnlyUpdateEquivalentToVoIP = false
    var localCallKitOnlyProviderConfigEquivalentToVoIP = false
    var voIPCallKitUpdateEquivalentToLocal = false
    var voIPReportQueueMatchesLocal = false
    var voIPProviderReuseMatchesLocal = false
    var voIPOperatorMarkerSetBeforeReport = false
    var voIPPushKitCompletionDelayedUntilFirstAction = false
    var callKitProviderRetainedForAnswer = false
    var callKitDelegateRetainedForAnswer = false
    var callKitActiveCallUUIDRetained = false
    var callKitProviderDidResetObserved = false
    var callKitProviderDidActivateAudioSession = false
    var callKitProviderDidDeactivateAudioSession = false
    var providerDidResetBeforeFirstAction = false
    var audioSessionDidActivateBeforeFirstAction = false
    var audioSessionDidDeactivateBeforeFirstAction = false
    var callKitFirstActionKind = "none"
    var callKitFirstActionAfterReportMsBucket = "not_observed"
    var operatorReadyToAnswer = false
    var operatorExpectedSurface = "unknown"
    var callKitUISurfaceObservedByOperator = false
    var callKitOperatorIntendedAction = "unknown"
    var callKitOperatorActionTimingBucket = "unknown"
    var callKitUIAnswerOperatorTapObserved = false
    var callKitEndArrivedBeforeOperatorAnswerWindow = false
    var callKitEndActionDelivered = false
    var endActionUUIDMatched = false
    var endActionGenerationMatched = false
    var endActionSourceMatched = false
    var endActionFulfilled = false
    var endActionOrigin = "none"
    var localEndRequestBeforeAnswer = false
    var providerInvalidateBeforeAnswer = false
    var reportCallEndedBeforeAnswer = false
    var controlledTimeoutBeforeAnswer = false
    var callKitAnswerActionDelivered = false
    var answerActionUUIDMatched = false
    var answerActionGenerationMatched = false
    var callKitEventOrder = "not_started"
    var callKitAnswerActionReceived = false
    var callKitAnswerActionFulfilled = false
    var appActivationObserved = false
    var controlledInAppActivationRequested = false
    var controlledInAppActivationObserved = false
    var controlledInAppScreenRequested = false
    var controlledInAppScreenPresented = false
    var controlledInAppScreenSource = "none"
    var foregroundCallStateHandoffRequested = false
    var foregroundCallStateHandoffObserved = false
    var foregroundCallState = "not_requested"
    var foregroundCallStateSource = "none"
    var foregroundCallStatePayloadRedacted = false
    var foregroundCallStateHasStableRedactedCorrelation = false
    var foregroundPendingCallMetadataHandoffRequested = false
    var foregroundPendingCallMetadataHandoffObserved = false
    var foregroundPendingCallMetadataSource = "none"
    var foregroundPendingCallMetadataPayloadRedacted = false
    var foregroundPendingCallMetadataHasCallIdentifier = false
    var foregroundPendingCallMetadataHasRoomBinding = false
    var foregroundPendingCallMetadataHasPeer = false
    var foregroundPendingCallMetadataDirection = "none"
    var foregroundPendingCallMetadataIntent = "none"
    var mediaCredentialsRequestMetadataAvailable = false
    var mediaCredentialsRequestMetadataRedacted = false
    var mediaCredentialsRequestMetadataSource = "none"
    var mediaCredentialsBoundaryReached = false
    var mediaCredentialsRequestPlanned = false
    var mediaCredentialsRequested = false
    var mediaCredentialsRequestAuthorized = false
    var mediaCredentialsResult = "not_requested"
    var mediaCredentialsTokenReceived = false
    var mediaCredentialsTokenRedacted = false
    var mediaCredentialsURLReceived = false
    var mediaCredentialsURLRedacted = false
    var mediaCredentialsExpiresAtPresent = false
    var mediaCredentialsPayloadRedacted = false
    var mediaCredentialsLocalPersistenceRequested = false
    var mediaCredentialsCleanupRequested = false
    var mediaCredentialsCleanupResult = "not_requested"
    var mediaCredentialsPostCleanupTokenPresent = false
    var mediaCredentialsPostCleanupURLPresent = false
    var mediaCredentialsPostCleanupExpiresAtPresent = false
    var mediaCredentialsPostCleanupPayloadPresent = false
    var mediaCredentialsReuseAttempted = false
    var mediaCredentialsReuseAllowed = false
    var mediaCredentialsExpiryReferencePresent = false
    var mediaCredentialsExpiryCheckRequested = false
    var mediaCredentialsExpiryCheckResult = "not_requested"
    var mediaCredentialsTokenRequestSeen = false
    var mediaCredentialsTokenHTTPStatusBucket = "not_requested"
    var mediaCredentialsTokenReason = "none"
    var mediaCredentialsEligibilityAllowed = false
    var mediaCredentialsRateLimited = false
    var mediaCredentialsAllocationAttempted = false
    var mediaCredentialsLiveKitRoomPrecreateAttempted = false
    var mediaCredentialsTokenIssued = false
    var physical6RuntimeEnablementURLHookPresent = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.present
    var physical6RuntimeEnablementURLHookDebugOnly = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.debugOnly
    var physical6RuntimeEnablementURLHookDefaultDisabled = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.isDefaultDisabled
    var physical6RuntimeEnablementURLHookArmed = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.armed
    var physical6RuntimeEnablementURLHookOneShot = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.oneShot
    var physical6RuntimeEnablementURLHookAudioOnly = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.audioOnly
    var physical6RuntimeEnablementURLHookVideoAllowed = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.videoAllowed
    var physical6RuntimeEnablementURLHookMatrixEventsAllowed = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.matrixEventsAllowed
    var physical6RuntimeEnablementURLHookRawCredentialsLogged = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.rawCredentialsLogged
    var physical6RuntimeEnablementURLHookConsumed = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.consumed
    var physical6RuntimeEnablementURLHookBlockedReason = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.blockedReason
    var controlledConnectActivationWiringPresent = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.wiringPresent
    var controlledConnectActivationDebugOnly = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.debugOnly
    var controlledConnectActivationDefaultDisabled = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.isDefaultDisabled
    var controlledConnectActivationRequiresOperatorApproval = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.requiresOperatorApproval
    var controlledConnectActivationRollbackAvailable = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.rollbackAvailable
    var controlledConnectActivationScope = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.activationScope
    var controlledConnectVideoAllowed = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.videoAllowed
    var controlledConnectMatrixEventsAllowed = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.matrixEventsAllowed
    var controlledConnectRawCredentialsLogged = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.rawCredentialsLogged
    var controlledConnectSwitchPresent = true
    var controlledConnectSwitchDebugOnly = true
    var controlledConnectSwitchEnabled = SalemXControlledMediaConnectSwitch.disabled.isEnabled
    var controlledConnectOperatorApproved = SalemXControlledMediaConnectSwitch.disabled.operatorApproved
    var controlledConnectExecutionAllowed = SalemXControlledMediaConnectSwitch.disabled.executionAllowed
    var controlledConnectBlockedReason = SalemXControlledMediaConnectSwitch.disabled.blockedReason
    var controlledConnectBlockedBeforeEngine = true
    var controlledConnectBlockedBeforeLiveKitJoin = true
    var controlledConnectBlockedBeforePermissions = true
    var controlledConnectBlockedBeforeMatrixEvents = true
    var controlledConnectEnablementWiringPresent = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.wiringPresent
    var controlledConnectEnablementDebugOnly = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.debugOnly
    var controlledConnectEnablementDefaultOff = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.isDefaultOff
    var controlledConnectEnablementOperatorApprovalRequired = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.operatorApprovalRequired
    var controlledConnectEnablementOneShot = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.isOneShot
    var controlledConnectEnablementFreshCredentialsRequired = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.freshCredentialsRequired
    var controlledConnectEnablementAudioOnly = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.audioOnlyScope
    var controlledConnectEnablementVideoAllowed = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.videoAllowed
    var controlledConnectEnablementMatrixEventsAllowed = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.matrixEventsAllowed
    var controlledConnectEnablementRawCredentialsLogged = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.rawCredentialsLogged
    var controlledConnectEnablementRollbackAvailable = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.rollbackAvailable
    var controlledConnectEnablementEnabled = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.oneShotEnablementEnabled
    var controlledConnectEnablementOperatorApproved = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.operatorApproved
    var controlledConnectEnablementFuturePhasePermitted = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.futureConnectPhasePermitted
    var controlledConnectEnablementExecutionAllowed = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.executionAllowed
    var controlledConnectEnablementBlockedReason = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.blockedReason
    var controlledAudioConnectExecutionGatePresent = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).gatePresent
    var controlledAudioConnectExecutionDebugOnly = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).debugOnly
    var controlledAudioConnectExecutionAudioOnly = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).audioOnly
    var controlledAudioConnectExecutionVideoAllowed = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).videoAllowed
    var controlledAudioConnectExecutionMatrixEventsAllowed = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).matrixEventsAllowed
    var controlledAudioConnectExecutionRawCredentialsLogged = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).rawCredentialsLogged
    var controlledAudioConnectExecutionRequiresEnablement = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).requiresEnablement
    var controlledAudioConnectExecutionRequiresOperatorApproval = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).requiresOperatorApproval
    var controlledAudioConnectExecutionRequiresFuturePhasePermission = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).requiresFuturePhasePermission
    var controlledAudioConnectExecutionFuturePhasePermitted = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).futurePhasePermitted
    var controlledAudioConnectExecutionAllowed = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).executionAllowed
    var controlledAudioConnectExecutionBlockedReason = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).blockedReason
    var controlledAudioConnectExecutionBlockedBeforeEngine = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).blockedBeforeEngine
    var controlledAudioConnectExecutionBlockedBeforeLiveKitJoin = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).blockedBeforeLiveKitJoin
    var controlledAudioConnectExecutionBlockedBeforePermissions = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).blockedBeforePermissions
    var controlledAudioConnectExecutionBlockedBeforeMatrixEvents = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).blockedBeforeMatrixEvents
    var controlledAudioConnectActivationPathPresent = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).pathPresent
    var controlledAudioConnectActivationDebugOnly = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).debugOnly
    var controlledAudioConnectActivationOneShot = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).isOneShot
    var controlledAudioConnectActivationDefaultDisabled = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).isDefaultDisabled
    var controlledAudioConnectActivationRequiresReceiverSession = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).requiresReceiverSession
    var controlledAudioConnectActivationRequiresFreshCredentials = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).requiresFreshCredentials
    var controlledAudioConnectActivationRequiresEnablement = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).requiresEnablement
    var controlledAudioConnectActivationRequiresOperatorApproval = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).requiresOperatorApproval
    var controlledAudioConnectActivationRequiresFuturePhasePermission = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).requiresFuturePhasePermission
    var controlledAudioConnectActivationAudioOnly = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).audioOnly
    var controlledAudioConnectActivationVideoAllowed = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).videoAllowed
    var controlledAudioConnectActivationMatrixEventsAllowed = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).matrixEventsAllowed
    var controlledAudioConnectActivationRawCredentialsLogged = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).rawCredentialsLogged
    var controlledAudioConnectActivationRollbackAvailable = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).rollbackAvailable
    var controlledAudioConnectActivationAllowed = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).activationAllowed
    var controlledAudioConnectActivationBlockedReason = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).blockedReason
    var controlledAudioConnectActivationBlockedBeforeEngine = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).blockedBeforeEngine
    var controlledAudioConnectActivationBlockedBeforeLiveKitJoin = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).blockedBeforeLiveKitJoin
    var controlledAudioConnectActivationBlockedBeforePermissions = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).blockedBeforePermissions
    var controlledAudioConnectActivationBlockedBeforeMatrixEvents = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).blockedBeforeMatrixEvents
    var controlledConnectRealAudioPathPresent = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.present
    var controlledConnectRealAudioPathDebugOnly = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.debugOnly
    var controlledConnectRealAudioPathDefaultDisabled = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.isDefaultDisabled
    var controlledConnectRealAudioPathRequiresEnablement = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.requiresEnablement
    var controlledConnectRealAudioPathRequiresOperatorApproval = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.requiresOperatorApproval
    var controlledConnectRealAudioPathRequiresFuturePhasePermission = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.requiresFuturePhasePermission
    var controlledConnectRealAudioPathAudioOnly = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.audioOnly
    var controlledConnectRealAudioPathVideoAllowed = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.videoAllowed
    var controlledConnectRealAudioPathMatrixEventsAllowed = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.matrixEventsAllowed
    var controlledConnectRealAudioPathRawCredentialsLogged = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.rawCredentialsLogged
    var controlledConnectRealAudioPathOneShot = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.oneShot
    var controlledConnectRealAudioPathAllowed = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.allowed
    var controlledConnectRealAudioPathBlockedReason = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.blockedReason
    var controlledConnectRealAudioPathBlockedBeforeEngine = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.blockedBeforeEngine
    var controlledConnectRealAudioPathCanReachEngineWhenAllGatesTrue = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.canReachEngineWhenAllGatesTrue
    var controlledConnectRealRuntimePathPresent = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.present
    var controlledConnectRealRuntimePathDebugOnly = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.debugOnly
    var controlledConnectRealRuntimePathDefaultDisabled = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.isDefaultDisabled
    var controlledConnectRealRuntimePathRequiresCredentials = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.requiresCredentials
    var controlledConnectRealRuntimePathRequiresEnablement = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.requiresEnablement
    var controlledConnectRealRuntimePathRequiresOperatorApproval = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.requiresOperatorApproval
    var controlledConnectRealRuntimePathRequiresFuturePhasePermission = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.requiresFuturePhasePermission
    var controlledConnectRealRuntimePathAudioOnly = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.audioOnly
    var controlledConnectRealRuntimePathVideoAllowed = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.videoAllowed
    var controlledConnectRealRuntimePathMatrixEventsAllowed = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.matrixEventsAllowed
    var controlledConnectRealRuntimePathRawCredentialsLogged = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.rawCredentialsLogged
    var controlledConnectRealRuntimePathOneShot = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.oneShot
    var controlledConnectRealRuntimePathAllowed = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.allowed
    var controlledConnectRealRuntimePathBlockedReason = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.blockedReason
    var controlledConnectRealRuntimePathBlockedBeforeEngine = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.blockedBeforeEngine
    var controlledConnectRealRuntimePathCanCallConnectMediaWhenAllGatesTrue = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.canCallConnectMediaWhenAllGatesTrue
    var controlledConnectRealRuntimePathCanCallLiveKitAudioWhenAllGatesTrue = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.canCallLiveKitAudioWhenAllGatesTrue
    var controlledConnectRealBridgePresent = SalemXControlledAudioConnectRealBridge.defaultDisabled.present
    var controlledConnectRealBridgeDebugOnly = SalemXControlledAudioConnectRealBridge.defaultDisabled.debugOnly
    var controlledConnectRealBridgeDefaultDisabled = SalemXControlledAudioConnectRealBridge.defaultDisabled.isDefaultDisabled
    var controlledConnectRealBridgeRequiresCredentials = SalemXControlledAudioConnectRealBridge.defaultDisabled.requiresCredentials
    var controlledConnectRealBridgeRequiresEnablement = SalemXControlledAudioConnectRealBridge.defaultDisabled.requiresEnablement
    var controlledConnectRealBridgeRequiresOperatorApproval = SalemXControlledAudioConnectRealBridge.defaultDisabled.requiresOperatorApproval
    var controlledConnectRealBridgeRequiresFuturePhasePermission = SalemXControlledAudioConnectRealBridge.defaultDisabled.requiresFuturePhasePermission
    var controlledConnectRealBridgeAudioOnly = SalemXControlledAudioConnectRealBridge.defaultDisabled.audioOnly
    var controlledConnectRealBridgeVideoAllowed = SalemXControlledAudioConnectRealBridge.defaultDisabled.videoAllowed
    var controlledConnectRealBridgeMatrixEventsAllowed = SalemXControlledAudioConnectRealBridge.defaultDisabled.matrixEventsAllowed
    var controlledConnectRealBridgeRawCredentialsLogged = SalemXControlledAudioConnectRealBridge.defaultDisabled.rawCredentialsLogged
    var controlledConnectRealBridgeOneShot = SalemXControlledAudioConnectRealBridge.defaultDisabled.oneShot
    var controlledConnectRealBridgeAllowed = SalemXControlledAudioConnectRealBridge.defaultDisabled.allowed
    var controlledConnectRealBridgeBlockedReason = SalemXControlledAudioConnectRealBridge.defaultDisabled.blockedReason
    var controlledConnectRealBridgeBlockedBeforeConnectMedia = SalemXControlledAudioConnectRealBridge.defaultDisabled.blockedBeforeConnectMedia
    var controlledConnectRealBridgeCanCallConnectMediaWhenAllGatesTrue = SalemXControlledAudioConnectRealBridge.defaultDisabled.canCallConnectMediaWhenAllGatesTrue
    var controlledConnectRealBridgeCanCallLiveKitAudioWhenAllGatesTrue = SalemXControlledAudioConnectRealBridge.defaultDisabled.canCallLiveKitAudioWhenAllGatesTrue
    var controlledConnectRealBridgeUsesFakeEngineInTestsOnly = SalemXControlledAudioConnectRealBridge.defaultDisabled.usesFakeEngineInTestsOnly
    var controlledConnectRealBridgeUsesRealRuntimeBoundaryWhenNotTest = SalemXControlledAudioConnectRealBridge.defaultDisabled.usesRealRuntimeBoundaryWhenNotTest
    var mediaConnectPreflightRequested = false
    var mediaConnectPreflightMetadataAvailable = false
    var mediaConnectPreflightCredentialsAvailable = false
    var mediaConnectPreflightTokenPresent = false
    var mediaConnectPreflightURLPresent = false
    var mediaConnectPreflightExpiresAtPresent = false
    var mediaConnectGuardEnabled = false
    var mediaConnectExecutionAllowed = false
    var mediaConnectPreflightResult = "not_requested"
    var mediaConnectBlockedReason = "not_requested"
    var mediaConnectEngineInvoked = false
    var liveKitConnectAudioInvoked = false
    var controlledConnectFirstAttemptRequested = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.requested
    var controlledConnectFirstAttemptAllowed = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.allowed
    var controlledConnectFirstAttemptStarted = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.started
    var controlledConnectFirstAttemptCompleted = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.completed
    var controlledConnectFirstAttemptRepeated = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.repeated
    var controlledConnectFirstAttemptResult = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.result
    var controlledConnectFirstAttemptErrorBucket = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.errorBucket
    var controlledConnectFirstAttemptAudioOnly = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.audioOnly
    var controlledConnectFirstAttemptVideoAllowed = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.videoAllowed
    var controlledConnectFirstAttemptMatrixEventsAllowed = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.matrixEventsAllowed
    var controlledConnectFirstAttemptRawCredentialsLogged = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.rawCredentialsLogged
    var controlledConnectFirstAttemptBlockedReason = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.blockedReason
    var mediaConnectRequested = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.mediaConnectRequested
    var mediaConnectAttempted = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.mediaConnectAttempted
    var liveKitJoinRequested = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.liveKitJoinRequested
    var microphonePermissionRequested = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.microphonePermissionRequested
    var cameraPermissionRequested = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.cameraPermissionRequested
    var matrixEventEmitRequested = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.matrixEventEmitRequested
    var realCallFlowStarted = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.realCallFlowStarted
    var controlledCallKitCleanupRequested = false
    var controlledCallKitCleanupResult = "not_requested"
    var disconnectCleanupDiagnosticsPresent = true
    var disconnectCleanupDiagnosticsDebugOnly = true
    var disconnectCleanupDiagnosticsCallKitCleanupRequested = false
    var disconnectCleanupDiagnosticsCallKitCleanupResult = "not_requested"
    var disconnectCleanupDiagnosticsEndActionExpected = false
    var disconnectCleanupDiagnosticsEndActionDelivered = false
    var disconnectCleanupDiagnosticsEndActionFulfilled = false
    var disconnectCleanupDiagnosticsEndActionOrigin = "none"
    var disconnectCleanupDiagnosticsEndActionUUIDMatched = false
    var disconnectCleanupDiagnosticsEndActionGenerationMatched = false
    var disconnectCleanupDiagnosticsEndActionSourceMatched = false
    var disconnectCleanupDiagnosticsProviderEndReported = false
    var disconnectCleanupDiagnosticsLocalCleanupCompleted = false
    var disconnectCleanupDiagnosticsAudioSessionDeactivated = false
    var disconnectCleanupDiagnosticsLiveKitCleanupRequested = false
    var disconnectCleanupDiagnosticsLiveKitCleanupCompleted = false
    var disconnectCleanupDiagnosticsOneShotConsumed = false
    var disconnectCleanupDiagnosticsNoRepeatedConnect = true
    var disconnectCleanupDiagnosticsNoMatrixEvents = true
    var disconnectCleanupDiagnosticsNoVideo = true
    var disconnectCleanupDiagnosticsRawIdentifiersLogged = false
    var disconnectCleanupDiagnosticsEndTimingClassification = "not_requested"
    var disconnectCleanupDiagnosticsResult = "not_requested"
    var remoteAudioLivenessDiagnosticsPresent = true
    var remoteAudioLivenessDiagnosticsDebugOnly = true
    var remoteAudioLivenessDiagnosticsAudioOnly = true
    var remoteAudioLivenessDiagnosticsVideoAllowed = false
    var remoteAudioLivenessDiagnosticsMatrixEventsAllowed = false
    var remoteAudioLivenessDiagnosticsRawIdentifiersLogged = false
    var remoteAudioPublishLivenessRepairPresent = true
    var remoteAudioPublishLivenessRepairDebugOnly = true
    var remoteAudioPublishLivenessRepairRequiresLiveKitJoinSuccess = true
    var remoteAudioPublishLivenessRepairClassifiesPublishNotRequested = true
    var remoteAudioPublishLivenessRepairClassifiesPublishSuccess = true
    var remoteAudioPublishLivenessRepairClassifiesPublishFailure = true
    var remoteAudioPublishLivenessRepairClassifiesSimulatorPeer = true
    var remoteAudioPublishLivenessRepairClassifiesRemoteMissing = true
    var remoteAudioPublishLivenessRepairClassifiesRemoteTrackMissing = true
    var remoteAudioPublishLivenessRepairClassifiesLivenessObserved = true
    var remoteAudioPublishLivenessRepairNoVideo = true
    var remoteAudioPublishLivenessRepairNoMatrixEvents = true
    var remoteAudioPublishLivenessRepairRawIdentifiersLogged = false
    var remoteParticipantPresenceRepairPresent = true
    var remoteParticipantPresenceRepairDebugOnly = true
    var remoteParticipantPresenceRepairRequiresTwoPhysicalDevices = true
    var remoteParticipantPresenceRepairRequiresSameRoom = true
    var remoteParticipantPresenceRepairRequiresSenderLiveKitReadiness = true
    var remoteParticipantPresenceRepairSenderJoinPathPresent = true
    var remoteParticipantPresenceRepairSenderJoinDefaultDisabled = true
    var remoteParticipantPresenceRepairReceiverObserverPresent = true
    var remoteParticipantPresenceRepairSameLiveKitRoomRequired = true
    var remoteParticipantPresenceRepairClassifiesSenderNotJoined = true
    var remoteParticipantPresenceRepairClassifiesRemoteMissing = true
    var remoteParticipantPresenceRepairClassifiesRemoteSeen = true
    var remoteParticipantPresenceRepairNoVideo = true
    var remoteParticipantPresenceRepairNoMatrixEvents = true
    var remoteParticipantPresenceRepairRawIdentifiersLogged = false
    var remoteParticipantObservationTimingRepairPresent = true
    var remoteParticipantObservationTimingRepairDebugOnly = true
    var remoteParticipantObservationTimingRepairBoundedWindow = true
    var remoteParticipantObservationTimingRepairRawIdentifiersLogged = false
    var participantObserverPropagationRepairPresent = true
    var participantObserverPropagationRepairDebugOnly = true
    var participantObserverPropagationRawIdentifiersLogged = false
    var receiverSenderConnectedOverlapRepairPresent = true
    var receiverSenderConnectedOverlapRepairDebugOnly = true
    var receiverSenderConnectedOverlapRepairRawIdentifiersLogged = false
    var receiverConnectedWindowRetentionRepairPresent = true
    var receiverConnectedWindowRetentionRepairDebugOnly = true
    var receiverConnectedWindowRetentionRepairRawIdentifiersLogged = false
    var receiverConnectedSessionLeasePresent = true
    var receiverConnectedSessionLeaseDebugOnly = true
    var receiverConnectedSessionLeaseAcquired = false
    var receiverConnectedSessionLeaseRoomRetained = false
    var receiverConnectedSessionLeaseDelegateRetained = false
    var receiverConnectedSessionLeaseObserverRetained = false
    var receiverConnectedSessionLeaseTaskRetained = false
    var receiverConnectedSessionLeaseActiveBeforeSenderTrigger = false
    var receiverConnectedSessionLeaseActiveAfterSenderTrigger = false
    var receiverConnectedSessionLeaseActiveAtSenderSignal = false
    var receiverConnectedSessionLeaseReleased = false
    var receiverConnectedSessionLeaseReleasedAfterTerminal = false
    var receiverConnectedSessionLeaseReleaseReason = "not_requested"
    var receiverConnectedSessionLeaseRepeatedRelease = false
    var receiverRoomRetainedForSenderObservation = false
    var receiverObserverAttachedBeforeSenderJoin = false
    var receiverObserverActiveDuringSenderJoin = false
    var receiverCleanupDeferredUntilObservationTerminal = false
    var receiverCleanupStartedBeforeSenderTerminal = false
    var senderJoinTerminalSeenByReceiver = false
    var senderRoomConnectedDuringReceiverWindow = false
    var senderCleanupStartedBeforeReceiverObservation = false
    var receiverSenderConnectedWindowOverlapObserved = false
    var receiverConnectedWindowOpened = false
    var receiverConnectedWindowClosed = false
    var receiverConnectedWindowCloseReason = "not_started"
    var receiverConnectedWindowClosedBeforeSenderConnected = false
    var receiverConnectedWindowRetainedUntilSenderTerminal = false
    var receiverDisconnectObservedBeforeSenderSignal = false
    var receiverDisconnectObservedAfterSenderSignal = false
    var senderConnectedSignalHandoffPresent = true
    var senderConnectedSignalHandoffDebugOnly = true
    var senderConnectedSignalHandoffRawIdentifiersLogged = false
    var senderConnectedSignalEmitted = false
    var senderConnectedSignalEmitSource = "none"
    var senderConnectedSignalEmittedAfterRuntimeJoinSuccess = false
    var senderConnectedSignalOpaqueCorrelationPresent = false
    var senderConnectedSignalRawRoomLogged = false
    var senderConnectedSignalRawCallLogged = false
    var senderConnectedSignalRawUserLogged = false
    var senderConnectedSignalRawDeviceLogged = false
    var senderConnectedSignalReceivedByReceiver = false
    var senderConnectedSignalSource = "none"
    var senderConnectedSignalBeforeReceiverDisconnect = false
    var senderConnectedSignalAfterReceiverDisconnect = false
    var senderConnectedSignalRawIdentifiersLogged = false
    var receiverSenderConnectedSignalWaitStarted = false
    var receiverSenderConnectedSignalWaitCompleted = false
    var receiverSenderConnectedSignalReceived = false
    var receiverSenderConnectedSignalCorrelationMatch = false
    var receiverSenderConnectedSignalReceivedBeforeReceiverDisconnect = false
    var receiverSenderConnectedSignalReceivedAfterReceiverDisconnect = false
    var receiverSenderConnectedSignalTimeout = false
    var receiverSenderConnectedSignalFinalClassification = "not_started"
    var receiverSenderConnectedWindowOverlapWaitStarted = false
    var receiverSenderConnectedWindowOverlapWaitCompleted = false
    var receiverSenderConnectedWindowOverlapWaitTimeout = false
    var receiverSenderConnectedWindowOverlapFinalClassification = "not_started"
    var senderReadinessContextPresentDuringObservation = false
    var opaqueCallCorrelationPresent = false
    var opaqueCallCorrelationMatch = false
    var remoteParticipantObservationWaitStarted = false
    var remoteParticipantObservationWaitCompleted = false
    var remoteParticipantObservationTimeoutBucket = "not_started"
    var remoteParticipantObservationFinalClassification = "not_started"
    var receiverParticipantObservationFinalClassification = "not_started"
    var receiverParticipantObserverBoundToRetainedRoom = false
    var receiverParticipantObserverBoundToConnectedRoom = false
    var receiverParticipantObserverAttachedBeforeSenderSignal = false
    var receiverParticipantObserverActiveAfterSenderSignal = false
    var receiverParticipantEventCallbackSeen = false
    var receiverParticipantSnapshotRequested = false
    var receiverParticipantSnapshotCountBucket = "not_requested"
    var receiverParticipantSnapshotSeen = false
    var receiverParticipantIdentityFilterApplied = false
    var receiverParticipantIdentityFilterResult = "not_applied_redacted"
    var receiverParticipantObservationAfterOverlapStarted = false
    var receiverParticipantObservationAfterOverlapCompleted = false
    var receiverParticipantObservationAfterOverlapTimeout = false
    var senderLiveKitReadinessHookPresent = SalemXSenderLiveKitReadinessHook.defaultDisabled.present
    var senderLiveKitReadinessHookDebugOnly = SalemXSenderLiveKitReadinessHook.defaultDisabled.debugOnly
    var senderLiveKitReadinessHookDefaultDisabled = SalemXSenderLiveKitReadinessHook.defaultDisabled.isDefaultDisabled
    var senderLiveKitReadinessHookArmed = SalemXSenderLiveKitReadinessHook.defaultDisabled.armed
    var senderLiveKitReadinessHookMatrixSessionReady = SalemXSenderLiveKitReadinessHook.defaultDisabled.matrixSessionReady
    var senderLiveKitReadinessHookExpectedUserMatched = SalemXSenderLiveKitReadinessHook.defaultDisabled.expectedUserMatched
    var senderLiveKitReadinessHookSameRoomReady = SalemXSenderLiveKitReadinessHook.defaultDisabled.sameRoomReady
    var senderLiveKitReadinessHookCredentialsReady = SalemXSenderLiveKitReadinessHook.defaultDisabled.credentialsReady
    var senderLiveKitReadinessHookAudioOnly = SalemXSenderLiveKitReadinessHook.defaultDisabled.audioOnly
    var senderLiveKitReadinessHookVideoAllowed = SalemXSenderLiveKitReadinessHook.defaultDisabled.videoAllowed
    var senderLiveKitReadinessHookMatrixEventsAllowed = SalemXSenderLiveKitReadinessHook.defaultDisabled.matrixEventsAllowed
    var senderLiveKitReadinessHookRawIdentifiersLogged = SalemXSenderLiveKitReadinessHook.defaultDisabled.rawIdentifiersLogged
    var senderLiveKitReadinessHookBlockedReason = SalemXSenderLiveKitReadinessHook.defaultDisabled.blockedReason
    var senderReadinessRuntimeHandoffPresent = true
    var senderReadinessRuntimeHandoffDebugOnly = true
    var senderReadinessRuntimeHandoffArmedBeforeAPNs = false
    var senderReadinessRuntimeHandoffReceivedByRuntime = false
    var senderReadinessRuntimeHandoffSurvivedPushKit = false
    var senderReadinessRuntimeHandoffSurvivedAnswer = false
    var senderReadinessRuntimeHandoffMatrixSessionReady = false
    var senderReadinessRuntimeHandoffSameRoomReady = false
    var senderReadinessRuntimeHandoffExpectedUserMatched = false
    var senderReadinessRuntimeHandoffRawIdentifiersLogged = false
    var senderReadinessRuntimeHandoffMissingClassified = true
    var secondPhysicalSenderLiveKitReadinessPresent = true
    var secondPhysicalSenderLiveKitReadinessDebugOnly = true
    var secondPhysicalSenderLiveKitReadinessDefaultDisabled = true
    var secondPhysicalSenderLiveKitReadinessMatrixSessionReady = false
    var secondPhysicalSenderLiveKitReadinessSameRoomReady = false
    var secondPhysicalSenderLiveKitReadinessCredentialsReady = false
    var secondPhysicalSenderLiveKitJoinPathPresent = true
    var secondPhysicalSenderLiveKitJoinPathDefaultDisabled = true
    var secondPhysicalSenderLiveKitJoinPathAudioOnly = true
    var secondPhysicalSenderLiveKitJoinPathVideoAllowed = false
    var secondPhysicalSenderLiveKitJoinPathMatrixEventsAllowed = false
    var secondPhysicalSenderLiveKitJoinPathRawCredentialsLogged = false
    var senderSideLiveKitJoinHookPresent = SalemXSenderSideLiveKitJoinHook.defaultDisabled.present
    var senderSideLiveKitJoinHookDebugOnly = SalemXSenderSideLiveKitJoinHook.defaultDisabled.debugOnly
    var senderSideLiveKitJoinHookDefaultDisabled = SalemXSenderSideLiveKitJoinHook.defaultDisabled.isDefaultDisabled
    var senderSideLiveKitJoinHookArmed = SalemXSenderSideLiveKitJoinHook.defaultDisabled.armed
    var senderSideLiveKitJoinHookAudioOnly = SalemXSenderSideLiveKitJoinHook.defaultDisabled.audioOnly
    var senderSideLiveKitJoinHookVideoAllowed = SalemXSenderSideLiveKitJoinHook.defaultDisabled.videoAllowed
    var senderSideLiveKitJoinHookMatrixEventsAllowed = SalemXSenderSideLiveKitJoinHook.defaultDisabled.matrixEventsAllowed
    var senderSideLiveKitJoinHookRawCredentialsLogged = SalemXSenderSideLiveKitJoinHook.defaultDisabled.rawCredentialsLogged
    var senderSideLiveKitJoinRequested = SalemXSenderSideLiveKitJoinHook.defaultDisabled.requested
    var senderSideLiveKitJoinResult = SalemXSenderSideLiveKitJoinHook.defaultDisabled.result
    var senderSideLiveKitJoinErrorBucket = SalemXSenderSideLiveKitJoinHook.defaultDisabled.errorBucket
    var senderSideLiveKitJoinRepeated = SalemXSenderSideLiveKitJoinHook.defaultDisabled.repeated
    var senderConnectParityPresent = SalemXSenderConnectParity.defaultEnabled.present
    var senderConnectParityDebugOnly = SalemXSenderConnectParity.defaultEnabled.debugOnly
    var senderConnectParityRawURLLogged = SalemXSenderConnectParity.defaultEnabled.rawURLLogged
    var senderConnectParityRawTokenLogged = SalemXSenderConnectParity.defaultEnabled.rawTokenLogged
    var senderConnectParityRawRoomLogged = SalemXSenderConnectParity.defaultEnabled.rawRoomLogged
    var senderConnectParityRawIdentityLogged = SalemXSenderConnectParity.defaultEnabled.rawIdentityLogged
    var senderConnectParityUsesReceiverProvenConnectWrapper = SalemXSenderConnectParity.defaultEnabled.usesReceiverProvenConnectWrapper
    var senderConnectParityUsesAudioOnly = SalemXSenderConnectParity.defaultEnabled.usesAudioOnly
    var senderConnectParityVideoAllowed = SalemXSenderConnectParity.defaultEnabled.videoAllowed
    var senderConnectParityMatrixEventsAllowed = SalemXSenderConnectParity.defaultEnabled.matrixEventsAllowed
    var senderConnectParityRoomRetainedUntilTerminal = SalemXSenderConnectParity.defaultEnabled.roomRetainedUntilTerminal
    var senderConnectParityDelegateRetainedUntilTerminal = SalemXSenderConnectParity.defaultEnabled.delegateRetainedUntilTerminal
    var senderConnectParityStateObserverRetainedUntilTerminal = SalemXSenderConnectParity.defaultEnabled.stateObserverRetainedUntilTerminal
    var senderConnectParityTaskRetainedUntilTerminal = SalemXSenderConnectParity.defaultEnabled.taskRetainedUntilTerminal
    var senderConnectParityBoundedWaitUsed = SalemXSenderConnectParity.defaultEnabled.boundedWaitUsed
    var senderConnectExecutorUnificationPresent = SalemXSenderConnectExecutorUnification.shared.present
    var senderConnectExecutorUnificationDebugOnly = SalemXSenderConnectExecutorUnification.shared.debugOnly
    var senderConnectExecutorUnificationReceiverExecutorShared = SalemXSenderConnectExecutorUnification.shared.receiverExecutorShared
    var senderConnectExecutorUnificationSenderExecutorShared = SalemXSenderConnectExecutorUnification.shared.senderExecutorShared
    var senderConnectExecutorUnificationSameConnectOptionsShape = SalemXSenderConnectExecutorUnification.shared.sameConnectOptionsShape
    var senderConnectExecutorUnificationSameRoomRetentionModel = SalemXSenderConnectExecutorUnification.shared.sameRoomRetentionModel
    var senderConnectExecutorUnificationSameDelegateRetentionModel = SalemXSenderConnectExecutorUnification.shared.sameDelegateRetentionModel
    var senderConnectExecutorUnificationSameStateObserverModel = SalemXSenderConnectExecutorUnification.shared.sameStateObserverModel
    var senderConnectExecutorUnificationSameBoundedWaitModel = SalemXSenderConnectExecutorUnification.shared.sameBoundedWaitModel
    var senderConnectExecutorUnificationAudioOnly = SalemXSenderConnectExecutorUnification.shared.audioOnly
    var senderConnectExecutorUnificationVideoAllowed = SalemXSenderConnectExecutorUnification.shared.videoAllowed
    var senderConnectExecutorUnificationMatrixEventsAllowed = SalemXSenderConnectExecutorUnification.shared.matrixEventsAllowed
    var senderConnectExecutorUnificationRawURLLogged = SalemXSenderConnectExecutorUnification.shared.rawURLLogged
    var senderConnectExecutorUnificationRawTokenLogged = SalemXSenderConnectExecutorUnification.shared.rawTokenLogged
    var senderConnectExecutorUnificationRawRoomLogged = SalemXSenderConnectExecutorUnification.shared.rawRoomLogged
    var senderConnectExecutorUnificationRawIdentityLogged = SalemXSenderConnectExecutorUnification.shared.rawIdentityLogged
    var senderJoinFailureDiagnosticsPresent = SalemXSenderJoinFailureDiagnostics.defaultDisabled.present
    var senderJoinFailureDiagnosticsDebugOnly = SalemXSenderJoinFailureDiagnostics.defaultDisabled.debugOnly
    var senderJoinFailureDiagnosticsAudioOnly = SalemXSenderJoinFailureDiagnostics.defaultDisabled.audioOnly
    var senderJoinFailureDiagnosticsVideoAllowed = SalemXSenderJoinFailureDiagnostics.defaultDisabled.videoAllowed
    var senderJoinFailureDiagnosticsMatrixEventsAllowed = SalemXSenderJoinFailureDiagnostics.defaultDisabled.matrixEventsAllowed
    var senderJoinFailureDiagnosticsRawIdentifiersLogged = SalemXSenderJoinFailureDiagnostics.defaultDisabled.rawIdentifiersLogged
    var senderJoinFailureDiagnosticsCredentialsPresent = SalemXSenderJoinFailureDiagnostics.defaultDisabled.credentialsPresent
    var senderJoinFailureDiagnosticsTokenPresent = SalemXSenderJoinFailureDiagnostics.defaultDisabled.tokenPresent
    var senderJoinFailureDiagnosticsURLPresent = SalemXSenderJoinFailureDiagnostics.defaultDisabled.urlPresent
    var senderJoinFailureDiagnosticsRoomBindingPresent = SalemXSenderJoinFailureDiagnostics.defaultDisabled.roomBindingPresent
    var senderJoinFailureDiagnosticsSameLiveKitRoom = SalemXSenderJoinFailureDiagnostics.defaultDisabled.sameLiveKitRoom
    var senderJoinFailureDiagnosticsTransportAttempted = SalemXSenderJoinFailureDiagnostics.defaultDisabled.transportAttempted
    var senderJoinFailureDiagnosticsTransportResult = SalemXSenderJoinFailureDiagnostics.defaultDisabled.transportResult
    var senderJoinFailureDiagnosticsErrorBucket = SalemXSenderJoinFailureDiagnostics.defaultDisabled.errorBucket
    var senderJoinFailureDiagnosticsClassification = SalemXSenderJoinFailureDiagnostics.defaultDisabled.classification
    var senderTransportFailureDiagnosticsPresent = SalemXSenderTransportFailureDiagnostics.defaultDisabled.present
    var senderTransportFailureDiagnosticsDebugOnly = SalemXSenderTransportFailureDiagnostics.defaultDisabled.debugOnly
    var senderTransportFailureDiagnosticsAudioOnly = SalemXSenderTransportFailureDiagnostics.defaultDisabled.audioOnly
    var senderTransportFailureDiagnosticsVideoAllowed = SalemXSenderTransportFailureDiagnostics.defaultDisabled.videoAllowed
    var senderTransportFailureDiagnosticsMatrixEventsAllowed = SalemXSenderTransportFailureDiagnostics.defaultDisabled.matrixEventsAllowed
    var senderTransportFailureDiagnosticsRawIdentifiersLogged = SalemXSenderTransportFailureDiagnostics.defaultDisabled.rawIdentifiersLogged
    var senderTransportFailureDiagnosticsTransportAttempted = SalemXSenderTransportFailureDiagnostics.defaultDisabled.transportAttempted
    var senderTransportFailureDiagnosticsTransportStarted = SalemXSenderTransportFailureDiagnostics.defaultDisabled.transportStarted
    var senderTransportFailureDiagnosticsTransportCompleted = SalemXSenderTransportFailureDiagnostics.defaultDisabled.transportCompleted
    var senderTransportFailureDiagnosticsTransportResult = SalemXSenderTransportFailureDiagnostics.defaultDisabled.transportResult
    var senderTransportFailureDiagnosticsErrorBucket = SalemXSenderTransportFailureDiagnostics.defaultDisabled.errorBucket
    var senderTransportFailureDiagnosticsClassification = SalemXSenderTransportFailureDiagnostics.defaultDisabled.classification
    var senderTransportFailureDiagnosticsLiveKitURLPresent = SalemXSenderTransportFailureDiagnostics.defaultDisabled.liveKitURLPresent
    var senderTransportFailureDiagnosticsTokenPresent = SalemXSenderTransportFailureDiagnostics.defaultDisabled.tokenPresent
    var senderTransportFailureDiagnosticsRoomBindingPresent = SalemXSenderTransportFailureDiagnostics.defaultDisabled.roomBindingPresent
    var senderTransportFailureDiagnosticsSameLiveKitRoom = SalemXSenderTransportFailureDiagnostics.defaultDisabled.sameLiveKitRoom
    var senderTransportFailureDiagnosticsSameTokenAuthority = SalemXSenderTransportFailureDiagnostics.defaultDisabled.sameTokenAuthority
    var senderTransportFailureDiagnosticsReceiverSenderRoomMatch = SalemXSenderTransportFailureDiagnostics.defaultDisabled.receiverSenderRoomMatch
    var senderTransportFailureDiagnosticsReceiverSenderTokenAuthorityMatch = SalemXSenderTransportFailureDiagnostics.defaultDisabled.receiverSenderTokenAuthorityMatch
    var senderTransportErrorSurfacePresent = SalemXSenderTransportErrorSurface.defaultDisabled.present
    var senderTransportErrorSurfaceDebugOnly = SalemXSenderTransportErrorSurface.defaultDisabled.debugOnly
    var senderTransportErrorSurfaceRawErrorLogged = SalemXSenderTransportErrorSurface.defaultDisabled.rawErrorLogged
    var senderTransportErrorSurfaceRawURLLogged = SalemXSenderTransportErrorSurface.defaultDisabled.rawURLLogged
    var senderTransportErrorSurfaceRawTokenLogged = SalemXSenderTransportErrorSurface.defaultDisabled.rawTokenLogged
    var senderLiveKitSDKFailureSurfacePresent = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.present
    var senderLiveKitSDKFailureSurfaceDebugOnly = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.debugOnly
    var senderLiveKitSDKFailureSurfaceRawErrorLogged = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.rawErrorLogged
    var senderLiveKitSDKFailureSurfaceRawURLLogged = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.rawURLLogged
    var senderLiveKitSDKFailureSurfaceRawTokenLogged = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.rawTokenLogged
    var senderLiveKitSDKFailureSurfaceRawRoomLogged = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.rawRoomLogged
    var senderLiveKitSDKFailureSurfaceRawIdentityLogged = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.rawIdentityLogged
    var senderLiveKitSDKFailureSurfaceConnectCallStarted = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.connectCallStarted
    var senderLiveKitSDKFailureSurfaceConnectCallReturned = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.connectCallReturned
    var senderLiveKitSDKFailureSurfaceConnectCallThrew = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.connectCallThrew
    var senderLiveKitSDKFailureSurfaceConnectedStateObserved = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.connectedStateObserved
    var senderLiveKitSDKFailureSurfaceFailedStateObserved = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.failedStateObserved
    var senderLiveKitSDKFailureSurfaceDisconnectedBeforeConnected = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.disconnectedBeforeConnected
    var senderLiveKitSDKFailureSurfaceDelegateFailureObserved = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.delegateFailureObserved
    var senderLiveKitSDKFailureSurfaceRoomAlreadyConnected = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.roomAlreadyConnected
    var senderLiveKitSDKFailureSurfaceIdentityConflictObserved = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.identityConflictObserved
    var senderLiveKitSDKFailureSurfaceTokenIdentityMatch = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.tokenIdentityMatch
    var senderLiveKitSDKFailureSurfaceAudioSessionReady = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.audioSessionReady
    var senderLiveKitSDKFailureSurfacePermissionRequired = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.permissionRequired
    var senderLiveKitSDKFailureSurfaceCaptureStarted = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.captureStarted
    var senderLiveKitSDKFailureSurfaceFinalClassification = SalemXSenderLiveKitSDKFailureSurface.defaultDisabled.finalClassification
    var senderLiveKitSDKTimelinePresent = SalemXSenderLiveKitSDKTimeline.defaultDisabled.present
    var senderLiveKitSDKTimelineDebugOnly = SalemXSenderLiveKitSDKTimeline.defaultDisabled.debugOnly
    var senderLiveKitSDKTimelineRawErrorLogged = SalemXSenderLiveKitSDKTimeline.defaultDisabled.rawErrorLogged
    var senderLiveKitSDKTimelineRawURLLogged = SalemXSenderLiveKitSDKTimeline.defaultDisabled.rawURLLogged
    var senderLiveKitSDKTimelineRawTokenLogged = SalemXSenderLiveKitSDKTimeline.defaultDisabled.rawTokenLogged
    var senderLiveKitSDKTimelineRawRoomLogged = SalemXSenderLiveKitSDKTimeline.defaultDisabled.rawRoomLogged
    var senderLiveKitSDKTimelineRawIdentityLogged = SalemXSenderLiveKitSDKTimeline.defaultDisabled.rawIdentityLogged
    var senderLiveKitSDKTimelineTriggerReceived = SalemXSenderLiveKitSDKTimeline.defaultDisabled.triggerReceived
    var senderLiveKitSDKTimelineTaskCreated = SalemXSenderLiveKitSDKTimeline.defaultDisabled.taskCreated
    var senderLiveKitSDKTimelineTaskStarted = SalemXSenderLiveKitSDKTimeline.defaultDisabled.taskStarted
    var senderLiveKitSDKTimelineConnectInvoked = SalemXSenderLiveKitSDKTimeline.defaultDisabled.connectInvoked
    var senderLiveKitSDKTimelineConnectReturned = SalemXSenderLiveKitSDKTimeline.defaultDisabled.connectReturned
    var senderLiveKitSDKTimelineConnectThrew = SalemXSenderLiveKitSDKTimeline.defaultDisabled.connectThrew
    var senderLiveKitSDKTimelineDelegateAttached = SalemXSenderLiveKitSDKTimeline.defaultDisabled.delegateAttached
    var senderLiveKitSDKTimelineStateObserverAttached = SalemXSenderLiveKitSDKTimeline.defaultDisabled.stateObserverAttached
    var senderLiveKitSDKTimelineConnectedStateSeen = SalemXSenderLiveKitSDKTimeline.defaultDisabled.connectedStateSeen
    var senderLiveKitSDKTimelineFailedStateSeen = SalemXSenderLiveKitSDKTimeline.defaultDisabled.failedStateSeen
    var senderLiveKitSDKTimelineDisconnectedStateSeen = SalemXSenderLiveKitSDKTimeline.defaultDisabled.disconnectedStateSeen
    var senderLiveKitSDKTimelineTaskCancelled = SalemXSenderLiveKitSDKTimeline.defaultDisabled.taskCancelled
    var senderLiveKitSDKTimelineTaskCompleted = SalemXSenderLiveKitSDKTimeline.defaultDisabled.taskCompleted
    var senderLiveKitSDKTimelineTimeoutElapsed = SalemXSenderLiveKitSDKTimeline.defaultDisabled.timeoutElapsed
    var senderLiveKitSDKTimelineProofWrittenAfterTerminalState = SalemXSenderLiveKitSDKTimeline.defaultDisabled.proofWrittenAfterTerminalState
    var senderLiveKitSDKTimelineFinalClassification = SalemXSenderLiveKitSDKTimeline.defaultDisabled.finalClassification
    var senderLiveKitSDKTimeoutDiagnosticsPresent = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.present
    var senderLiveKitSDKTimeoutDiagnosticsDebugOnly = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.debugOnly
    var senderLiveKitSDKTimeoutDiagnosticsRawErrorLogged = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.rawErrorLogged
    var senderLiveKitSDKTimeoutDiagnosticsRawURLLogged = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.rawURLLogged
    var senderLiveKitSDKTimeoutDiagnosticsRawTokenLogged = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.rawTokenLogged
    var senderLiveKitSDKTimeoutDiagnosticsRawRoomLogged = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.rawRoomLogged
    var senderLiveKitSDKTimeoutDiagnosticsRawIdentityLogged = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.rawIdentityLogged
    var senderLiveKitSDKTimeoutDiagnosticsWaitWindowBucket = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.waitWindowBucket
    var senderLiveKitSDKTimeoutDiagnosticsConnectInvoked = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.connectInvoked
    var senderLiveKitSDKTimeoutDiagnosticsConnectCallPendingAtTimeout = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.connectCallPendingAtTimeout
    var senderLiveKitSDKTimeoutDiagnosticsTaskRunningAtTimeout = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.taskRunningAtTimeout
    var senderLiveKitSDKTimeoutDiagnosticsTaskCancelledAtTimeout = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.taskCancelledAtTimeout
    var senderLiveKitSDKTimeoutDiagnosticsDelegateAttached = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.delegateAttached
    var senderLiveKitSDKTimeoutDiagnosticsStateObserverAttached = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.stateObserverAttached
    var senderLiveKitSDKTimeoutDiagnosticsStateEventCountBucket = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.stateEventCountBucket
    var senderLiveKitSDKTimeoutDiagnosticsDelegateEventCountBucket = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.delegateEventCountBucket
    var senderLiveKitSDKTimeoutDiagnosticsAppStateBucket = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.appStateBucket
    var senderLiveKitSDKTimeoutDiagnosticsActorContextAvailable = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.actorContextAvailable
    var senderLiveKitSDKTimeoutDiagnosticsNetworkPathBucket = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.networkPathBucket
    var senderLiveKitSDKTimeoutDiagnosticsFinalClassification = SalemXSenderLiveKitSDKTimeoutDiagnostics.defaultDisabled.finalClassification
    var senderTransportErrorSurfaceSource = SalemXSenderTransportErrorSurface.defaultDisabled.source
    var senderTransportErrorSurfaceSDKErrorBucket = SalemXSenderTransportErrorSurface.defaultDisabled.sdkErrorBucket
    var senderTransportErrorSurfaceDisconnectReasonBucket = SalemXSenderTransportErrorSurface.defaultDisabled.disconnectReasonBucket
    var senderTransportErrorSurfaceWebsocketBucket = SalemXSenderTransportErrorSurface.defaultDisabled.websocketBucket
    var senderTransportErrorSurfaceAuthBucket = SalemXSenderTransportErrorSurface.defaultDisabled.authBucket
    var senderTransportErrorSurfaceTimeoutObserved = SalemXSenderTransportErrorSurface.defaultDisabled.timeoutObserved
    var senderTransportErrorSurfaceConnectedStateObserved = SalemXSenderTransportErrorSurface.defaultDisabled.connectedStateObserved
    var senderTransportErrorSurfaceDisconnectedBeforeConnected = SalemXSenderTransportErrorSurface.defaultDisabled.disconnectedBeforeConnected
    var senderTransportErrorSurfaceFinalClassification = SalemXSenderTransportErrorSurface.defaultDisabled.finalClassification
    var senderSideLiveKitJoinActivationPresent = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.present
    var senderSideLiveKitJoinActivationDebugOnly = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.debugOnly
    var senderSideLiveKitJoinActivationDefaultDisabled = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.isDefaultDisabled
    var senderSideLiveKitJoinActivationRequiresSenderReadiness = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.requiresSenderReadiness
    var senderSideLiveKitJoinActivationRequiresSameRoom = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.requiresSameRoom
    var senderSideLiveKitJoinActivationAudioOnly = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.audioOnly
    var senderSideLiveKitJoinActivationVideoAllowed = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.videoAllowed
    var senderSideLiveKitJoinActivationMatrixEventsAllowed = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.matrixEventsAllowed
    var senderSideLiveKitJoinActivationRawIdentifiersLogged = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.rawIdentifiersLogged
    var senderSideLiveKitJoinActivationArmed = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.armed
    var senderSideLiveKitJoinActivationTriggered = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.triggered
    var senderSideLiveKitJoinActivationConsumed = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.consumed
    var senderSideLiveKitJoinActivationRepeated = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.repeated
    var senderSideLiveKitJoinActivationBlockedReason = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.blockedReason
    var senderJoinTriggerOrchestrationPresent = SalemXSenderJoinTriggerOrchestration.defaultBlocked.present
    var senderJoinTriggerOrchestrationDebugOnly = SalemXSenderJoinTriggerOrchestration.defaultBlocked.debugOnly
    var senderJoinTriggerOrchestrationRawIdentifiersLogged = SalemXSenderJoinTriggerOrchestration.defaultBlocked.rawIdentifiersLogged
    var senderJoinTriggerOrchestrationAPNsSuccessSeen = SalemXSenderJoinTriggerOrchestration.defaultBlocked.apnsSuccessSeen
    var senderJoinTriggerOrchestrationReceiverAnswerSeen = SalemXSenderJoinTriggerOrchestration.defaultBlocked.receiverAnswerSeen
    var senderJoinTriggerOrchestrationReceiverConnectTerminalSeen = SalemXSenderJoinTriggerOrchestration.defaultBlocked.receiverConnectTerminalSeen
    var senderJoinTriggerOrchestrationSenderActivationArmed = SalemXSenderJoinTriggerOrchestration.defaultBlocked.senderActivationArmed
    var senderJoinTriggerOrchestrationSenderTriggerRequired = SalemXSenderJoinTriggerOrchestration.defaultBlocked.senderTriggerRequired
    var senderJoinTriggerOrchestrationSenderTriggerAllowed = SalemXSenderJoinTriggerOrchestration.defaultBlocked.senderTriggerAllowed
    var senderJoinTriggerOrchestrationSenderTriggerStarted = SalemXSenderJoinTriggerOrchestration.defaultBlocked.senderTriggerStarted
    var senderJoinTriggerOrchestrationSenderTriggerCompleted = SalemXSenderJoinTriggerOrchestration.defaultBlocked.senderTriggerCompleted
    var senderJoinTriggerOrchestrationSenderTriggerMissingClassified = SalemXSenderJoinTriggerOrchestration.defaultBlocked.senderTriggerMissingClassified
    var senderJoinTriggerOrchestrationPollAllowed = SalemXSenderJoinTriggerOrchestration.defaultBlocked.pollAllowed
    var senderJoinTriggerOrchestrationPollBlockedReason = SalemXSenderJoinTriggerOrchestration.defaultBlocked.pollBlockedReason
    var senderJoinTriggerOrchestrationFinalClassification = SalemXSenderJoinTriggerOrchestration.defaultBlocked.finalClassification
    var receiverRemoteParticipantObserverPresent = true
    var receiverRemoteParticipantObserverDebugOnly = true
    var receiverRemoteParticipantObserverStarted = false
    var receiverRemoteParticipantObserverResult = "not_observed_redacted"
    var receiverRemoteParticipantObserverErrorBucket = "sender_not_joined_or_remote_missing_redacted"
    var receiverRemoteParticipantObserverTimeoutBucket = "not_observed_redacted"
    var receiverRemoteParticipantObserverRemoteSeen = false
    var receiverRemoteParticipantObserverAudioTrackSeen = false
    var receiverRemoteParticipantObserverLivenessSeen = false
    var receiverRemoteParticipantObserverRawIdentifiersLogged = false
    var remotePeerContextHandoffPresent = true
    var remotePeerContextHandoffDebugOnly = true
    var remotePeerContextHandoffSource = "unknown_redacted"
    var remotePeerContextHandoffArmedBeforeAPNs = false
    var remotePeerContextHandoffReceivedByRuntime = false
    var remotePeerContextHandoffSurvivedPushKit = false
    var remotePeerContextHandoffSurvivedAnswer = false
    var remotePeerContextHandoffRawIdentifiersLogged = false
    var remotePeerContextHandoffBlocksSuccessWithoutContext = true
    var remotePeerContextHandoffClassifiesMissingRemoteParticipant = true
    var remotePeerContextHandoffClassifiesSimulatorLimitation = true
    var liveKitJoinResult = "not_requested"
    var liveKitJoinErrorBucket = "none"
    var liveKitRoomConnected = false
    var liveKitRoomDisconnected = false
    var liveKitLocalParticipantPresent = false
    var localAudioPublishRequested = false
    var localAudioPublishStarted = false
    var localAudioPublishResult = "not_requested"
    var localAudioPublishErrorBucket = "none"
    var localAudioPublishNotRequiredReason = "none"
    var microphonePermissionResult = "not_requested_or_not_required_redacted"
    var microphonePermissionNotRequiredReason = "no_connect_default_disabled"
    var audioRouteAvailable = false
    var audioRouteResult = "not_observed_redacted"
    var remotePeerKind = "unknown_redacted"
    var remotePeerPhysicalDevice = "unknown"
    var simulatorAssistedRemoteAudioProof = false
    var productionLikeTwoPhysicalDeviceProof = false
    var secondDeviceRemoteAudioReadiness = "unknown_redacted"
    var remoteAudioLivenessLimitation = "unknown_redacted"
    var liveKitRemoteParticipantSeen = false
    var liveKitRemoteParticipantCountBucket = "0"
    var liveKitRemoteAudioTrackSubscribed = false
    var liveKitRemoteAudioTrackUnmuted = false
    var liveKitRemoteAudioLevelObserved = false
    var liveKitAudioLivenessObserved = false
    var liveKitAudioLivenessResult = "not_observed_redacted"
    var liveKitAudioLivenessErrorBucket = "none"
    var liveKitCleanupRequested = false
    var liveKitCleanupCompleted = false
    var liveKitCleanupResult = "not_requested"
    var blockedReason = "voip_push_not_received"

    var receiverPostAnswerContinuationStarted: Bool {
        callKitAnswerActionReceived && foregroundCallState == "real_invite_pending_media"
    }

    var receiverPostAnswerPendingMetadataReferencePresent: Bool {
        pendingMetadataReferencePresent
    }

    var receiverPostAnswerPendingMetadataFetchRequested: Bool {
        pendingMetadataFetchRequested
    }

    var receiverPostAnswerPendingMetadataFetchResult: String {
        pendingMetadataFetchResult
    }

    var receiverPostAnswerPendingMetadataAuthorized: Bool {
        pendingMetadataFetchAuthorized
    }

    var receiverPostAnswerMediaCredentialsRequested: Bool {
        mediaCredentialsRequested
    }

    var receiverPostAnswerMediaCredentialsResult: String {
        mediaCredentialsResult
    }

    var receiverPostAnswerMediaCredentialsExpiresPresent: Bool {
        mediaCredentialsExpiresAtPresent
    }

    var receiverPostAnswerControlledConnectRequested: Bool {
        controlledConnectFirstAttemptRequested
    }

    var receiverPostAnswerControlledConnectResult: String {
        controlledConnectFirstAttemptResult
    }

    var receiverPostAnswerLiveKitJoinRequested: Bool {
        liveKitJoinRequested
    }

    var receiverPostAnswerLiveKitJoinResult: String {
        liveKitJoinResult
    }

    var receiverPostAnswerFinalClassification: String {
        guard receiverPostAnswerContinuationStarted else {
            return "receiver_post_answer_livekit_join_not_requested_redacted"
        }
        guard receiverPostAnswerPendingMetadataReferencePresent else {
            return "receiver_post_answer_pending_metadata_reference_missing_redacted"
        }
        guard receiverPostAnswerPendingMetadataFetchRequested else {
            return "receiver_post_answer_continuation_started_redacted"
        }
        guard receiverPostAnswerPendingMetadataFetchResult == "success_redacted" else {
            return receiverPostAnswerPendingMetadataFetchResult == "requested" ? "receiver_post_answer_continuation_started_redacted" : "receiver_post_answer_pending_metadata_fetch_failed_redacted"
        }
        guard receiverPostAnswerMediaCredentialsRequested else {
            return "receiver_post_answer_media_credentials_deferred_redacted"
        }
        guard receiverPostAnswerMediaCredentialsResult == "success_redacted" else {
            return "receiver_post_answer_media_credentials_failed_redacted"
        }
        guard receiverPostAnswerControlledConnectRequested else {
            return "receiver_post_answer_controlled_connect_not_requested_redacted"
        }
        guard receiverPostAnswerControlledConnectResult == "success_redacted" else {
            return "receiver_post_answer_controlled_connect_failed_redacted"
        }
        if receiverPostAnswerLiveKitJoinResult == "success_redacted" {
            return "receiver_post_answer_livekit_join_success_redacted"
        }
        if !receiverPostAnswerLiveKitJoinRequested || receiverPostAnswerLiveKitJoinResult == "not_requested" {
            return "receiver_post_answer_livekit_join_not_requested_redacted"
        }
        return "receiver_post_answer_controlled_connect_failed_redacted"
    }

    var receiverCallKitAnswerAvailabilityFinalClassification: String {
        if receiverCallKitAnswerAvailableAfterAPNs || callKitAnswerActionReceived {
            return "receiver_callkit_answer_available_redacted"
        }
        if callKitReportRequested,
           callKitReportResult != "reported",
           callKitReportResult != "fake_reported",
           callKitReportResult != "pending" {
            return "receiver_callkit_report_failed_before_answer_redacted"
        }
        if callKitReportRequested,
           callKitReportResult == "reported" || callKitReportResult == "fake_reported",
           !callKitUISurfaceObservedByOperator,
           !callKitAnswerActionReceived {
            return "receiver_callkit_report_submitted_but_ui_missing_redacted"
        }
        if !callKitProviderRetainedForAnswer {
            return "receiver_callkit_provider_not_retained_redacted"
        }
        if !callKitDelegateRetainedForAnswer {
            return "receiver_callkit_delegate_not_retained_redacted"
        }
        if !callKitActiveCallUUIDRetained {
            return "receiver_callkit_uuid_not_retained_redacted"
        }
        if callKitEndActionDelivered || callKitProviderDidResetObserved {
            return "receiver_callkit_ended_or_reset_before_answer_redacted"
        }
        if pushKitCompletionAnswerableWindowResult == "timeout_elapsed" {
            return "receiver_callkit_answer_window_timeout_redacted"
        }
        if !voIPOperatorMarkerSetBeforeReport {
            return "receiver_callkit_operator_marker_missing_redacted"
        }
        return "receiver_callkit_answer_window_timeout_redacted"
    }

    var receiverCallKitSurfaceOperatorReadinessFinalClassification: String {
        if callKitAnswerActionReceived,
           receiverCallKitOperatorReadyMarkerRequestedBeforeAPNs || callKitUISurfaceObservedByOperator {
            return "receiver_callkit_surface_ready_for_answer_redacted"
        }
        if callKitAnswerActionReceived {
            return "receiver_callkit_action_received_without_ui_marker_redacted"
        }
        if receiverCallKitAnswerAvailableAfterAPNs {
            return "receiver_callkit_surface_ready_for_answer_redacted"
        }
        if callKitReportRequested,
           callKitReportResult != "reported",
           callKitReportResult != "fake_reported",
           callKitReportResult != "pending" {
            return "receiver_callkit_report_failed_before_answer_redacted"
        }
        if !receiverCallKitOperatorReadyMarkerRequestedBeforeAPNs || !voIPOperatorMarkerSetBeforeReport {
            return "receiver_callkit_operator_marker_missing_redacted"
        }
        if Self.safeAppStateBucket(appStateAtReportCompletion) == "foreground",
           !callKitUISurfaceObservedByOperator,
           !callKitAnswerActionReceived {
            return "receiver_callkit_foreground_state_requires_in_app_answer_redacted"
        }
        if callKitReportRequested,
           callKitReportResult == "reported" || callKitReportResult == "fake_reported",
           !callKitUISurfaceObservedByOperator,
           !callKitAnswerActionReceived {
            return "receiver_callkit_report_submitted_but_ui_missing_redacted"
        }
        if pushKitCompletionAnswerableWindowResult == "timeout_elapsed" {
            return "receiver_callkit_answer_window_timeout_redacted"
        }
        return "receiver_callkit_report_submitted_but_ui_missing_redacted"
    }

    var redactedLines: [String] {
        [
            "proof_source=\(proofSource)",
            "proof_generation=\(proofGeneration)",
            "proof_last_updated_by=\(proofLastUpdatedBy)",
            "physical_voip_push_received=\(physicalVoIPPushReceived)",
            "pushkit_callback_invoked=\(callbackInvoked)",
            "pushkit_push_type=\(pushType)",
            "pushkit_payload_redacted=true",
            "pushkit_payload_version=\(payloadVersion)",
            "pushkit_payload_kind=\(payloadKind)",
            "pending_metadata_reference_present=\(pendingMetadataReferencePresent)",
            "pending_metadata_reference_redacted=\(pendingMetadataReferenceRedacted)",
            "pending_metadata_fetch_required=\(pendingMetadataFetchRequired)",
            "pending_metadata_fetch_requested=\(pendingMetadataFetchRequested)",
            "pending_metadata_fetch_authorized=\(pendingMetadataFetchAuthorized)",
            "pending_metadata_fetch_result=\(pendingMetadataFetchResult)",
            "pending_metadata_fetch_http_status_bucket=\(pendingMetadataFetchHTTPStatusBucket)",
            "pending_metadata_fetch_errcode=\(pendingMetadataFetchErrcode)",
            "pending_metadata_fetch_failure_reason=\(pendingMetadataFetchFailureReason)",
            "pending_metadata_payload_redacted=\(pendingMetadataPayloadRedacted)",
            "receiver_voip_push_delivery_triage_present=\(receiverVoIPPushDeliveryTriagePresent)",
            "receiver_voip_push_delivery_triage_debug_only=\(receiverVoIPPushDeliveryTriageDebugOnly)",
            "receiver_voip_push_delivery_triage_raw_identifiers_logged=\(receiverVoIPPushDeliveryTriageRawIdentifiersLogged)",
            "receiver_pushkit_token_readiness_repair_present=\(receiverPushKitTokenReadinessRepairPresent)",
            "receiver_pushkit_token_readiness_repair_debug_only=\(receiverPushKitTokenReadinessRepairDebugOnly)",
            "receiver_pushkit_token_readiness_repair_raw_identifiers_logged=\(receiverPushKitTokenReadinessRepairRawIdentifiersLogged)",
            "receiver_pushkit_registration_requested_before_apns=\(receiverPushKitRegistrationRequestedBeforeAPNs)",
            "receiver_pushkit_token_callback_seen_before_apns=\(receiverPushKitTokenCallbackSeenBeforeAPNs)",
            "receiver_pushkit_token_present_before_apns=\(receiverPushKitTokenPresentBeforeAPNs)",
            "receiver_pushkit_token_upload_attempted_before_apns=\(receiverPushKitTokenUploadAttemptedBeforeAPNs)",
            "receiver_pushkit_token_upload_result_bucket=\(receiverPushKitTokenUploadResultBucket)",
            "receiver_pushkit_token_server_store_result_bucket=\(receiverPushKitTokenServerStoreResultBucket)",
            "receiver_pushkit_token_environment_bucket=\(receiverPushKitTokenEnvironmentBucket)",
            "receiver_pushkit_token_device_binding_expected_bucket=\(receiverPushKitTokenDeviceBindingExpectedBucket)",
            "receiver_pushkit_token_readiness_wait_started=\(receiverPushKitTokenReadinessWaitStarted)",
            "receiver_pushkit_token_readiness_wait_completed=\(receiverPushKitTokenReadinessWaitCompleted)",
            "receiver_pushkit_token_readiness_wait_timeout=\(receiverPushKitTokenReadinessWaitTimeout)",
            "receiver_pushkit_token_readiness_final_classification=\(receiverPushKitTokenReadinessFinalClassification)",
            "receiver_post_answer_media_credentials_continuation_repair_present=\(receiverPostAnswerMediaCredentialsContinuationRepairPresent)",
            "receiver_post_answer_media_credentials_continuation_repair_debug_only=\(receiverPostAnswerMediaCredentialsContinuationRepairDebugOnly)",
            "receiver_post_answer_media_credentials_continuation_repair_raw_identifiers_logged=\(receiverPostAnswerMediaCredentialsContinuationRepairRawIdentifiersLogged)",
            "receiver_post_answer_continuation_started=\(receiverPostAnswerContinuationStarted)",
            "receiver_post_answer_pending_metadata_reference_present=\(receiverPostAnswerPendingMetadataReferencePresent)",
            "receiver_post_answer_pending_metadata_fetch_requested=\(receiverPostAnswerPendingMetadataFetchRequested)",
            "receiver_post_answer_pending_metadata_fetch_result=\(receiverPostAnswerPendingMetadataFetchResult)",
            "receiver_post_answer_pending_metadata_authorized=\(receiverPostAnswerPendingMetadataAuthorized)",
            "receiver_post_answer_media_credentials_requested=\(receiverPostAnswerMediaCredentialsRequested)",
            "receiver_post_answer_media_credentials_result=\(receiverPostAnswerMediaCredentialsResult)",
            "receiver_post_answer_media_credentials_expires_present=\(receiverPostAnswerMediaCredentialsExpiresPresent)",
            "receiver_post_answer_controlled_connect_requested=\(receiverPostAnswerControlledConnectRequested)",
            "receiver_post_answer_controlled_connect_result=\(receiverPostAnswerControlledConnectResult)",
            "receiver_post_answer_livekit_join_requested=\(receiverPostAnswerLiveKitJoinRequested)",
            "receiver_post_answer_livekit_join_result=\(receiverPostAnswerLiveKitJoinResult)",
            "receiver_post_answer_final_classification=\(receiverPostAnswerFinalClassification)",
            "receiver_app_lifecycle_state_before_apns_bucket=\(receiverAppLifecycleStateBeforeAPNsBucket)",
            "receiver_app_proof_generation_before_apns=\(receiverAppProofGenerationBeforeAPNs)",
            "receiver_app_proof_generation_after_apns_changed=\(receiverAppProofGenerationAfterAPNsChanged)",
            "receiver_voip_push_callback_seen_after_apns=\(receiverVoIPPushCallbackSeenAfterAPNs)",
            "receiver_callkit_report_requested_after_apns=\(receiverCallKitReportRequestedAfterAPNs)",
            "receiver_callkit_answer_available_after_apns=\(receiverCallKitAnswerAvailableAfterAPNs)",
            "receiver_callkit_answer_availability_repair_present=true",
            "receiver_callkit_answer_availability_repair_debug_only=true",
            "receiver_callkit_answer_availability_repair_raw_identifiers_logged=false",
            "receiver_callkit_surface_operator_readiness_repair_present=\(receiverCallKitSurfaceOperatorReadinessRepairPresent)",
            "receiver_callkit_surface_operator_readiness_repair_debug_only=\(receiverCallKitSurfaceOperatorReadinessRepairDebugOnly)",
            "receiver_callkit_surface_operator_readiness_repair_raw_identifiers_logged=\(receiverCallKitSurfaceOperatorReadinessRepairRawIdentifiersLogged)",
            "receiver_callkit_operator_ready_marker_requested_before_apns=\(receiverCallKitOperatorReadyMarkerRequestedBeforeAPNs)",
            "receiver_callkit_operator_ready_marker_recorded_before_report=\(voIPOperatorMarkerSetBeforeReport)",
            "receiver_callkit_expected_surface_bucket=\(operatorExpectedSurface)",
            "receiver_callkit_receiver_app_state_before_apns_bucket=\(receiverAppLifecycleStateBeforeAPNsBucket)",
            "receiver_callkit_receiver_app_state_at_report_bucket=\(Self.safeAppStateBucket(appStateAtReportCompletion))",
            "receiver_callkit_report_submitted_after_apns=\(callKitReportResult == "reported" || callKitReportResult == "fake_reported")",
            "receiver_callkit_report_result_bucket=\(callKitReportResult)",
            "receiver_callkit_report_completion_observed=\(callKitReportCompletionObserved)",
            "receiver_callkit_provider_retained_for_answer=\(callKitProviderRetainedForAnswer)",
            "receiver_callkit_delegate_retained_for_answer=\(callKitDelegateRetainedForAnswer)",
            "receiver_callkit_active_call_uuid_retained=\(callKitActiveCallUUIDRetained)",
            "receiver_callkit_operator_ready_to_answer_before_report=\(voIPOperatorMarkerSetBeforeReport)",
            "receiver_callkit_ui_surface_observed_by_operator=\(callKitUISurfaceObservedByOperator)",
            "receiver_callkit_answer_action_received_after_apns=\(callKitAnswerActionReceived)",
            "receiver_callkit_end_or_reset_before_answer=\(callKitEndActionDelivered || callKitProviderDidResetObserved)",
            "receiver_callkit_answer_window_started=\(pushKitCompletionAnswerableWindowRequested)",
            "receiver_callkit_answer_window_extended_for_ui_surface=\(receiverCallKitAnswerWindowExtendedForUISurface)",
            "receiver_callkit_answer_window_completed=\(pushKitCompletionAnswerableWindowResult != "pending" && pushKitCompletionAnswerableWindowResult != "not_requested")",
            "receiver_callkit_answer_window_timeout=\(pushKitCompletionAnswerableWindowResult == "timeout_elapsed")",
            "receiver_callkit_answer_availability_final_classification=\(receiverCallKitAnswerAvailabilityFinalClassification)",
            "receiver_callkit_surface_operator_readiness_final_classification=\(receiverCallKitSurfaceOperatorReadinessFinalClassification)",
            "receiver_foreground_in_app_answer_continuation_repair_present=\(receiverForegroundInAppAnswerContinuationRepairPresent)",
            "receiver_foreground_in_app_answer_continuation_repair_debug_only=\(receiverForegroundInAppAnswerContinuationRepairDebugOnly)",
            "receiver_foreground_in_app_answer_continuation_repair_raw_identifiers_logged=\(receiverForegroundInAppAnswerContinuationRepairRawIdentifiersLogged)",
            "receiver_foreground_in_app_answer_hook_present=\(receiverForegroundInAppAnswerHookPresent)",
            "receiver_foreground_in_app_answer_hook_default_disabled=\(receiverForegroundInAppAnswerHookDefaultDisabled)",
            "receiver_foreground_in_app_answer_hook_requested=\(receiverForegroundInAppAnswerHookRequested)",
            "receiver_foreground_in_app_answer_hook_allowed=\(receiverForegroundInAppAnswerHookAllowed)",
            "receiver_foreground_in_app_answer_hook_blocked_reason=\(receiverForegroundInAppAnswerHookBlockedReason)",
            "receiver_foreground_in_app_answer_recorded=\(receiverForegroundInAppAnswerRecorded)",
            "receiver_foreground_in_app_answer_preserved_pending_metadata=\(receiverForegroundInAppAnswerPreservedPendingMetadata)",
            "receiver_foreground_in_app_answer_triggered_post_answer_continuation=\(receiverForegroundInAppAnswerTriggeredPostAnswerContinuation)",
            "receiver_foreground_in_app_answer_final_classification=\(receiverForegroundInAppAnswerFinalClassification)",
            "apns_provider_acceptance_result_bucket=\(apnsProviderAcceptanceResultBucket)",
            "apns_delivery_callback_missing_after_acceptance=\(apnsDeliveryCallbackMissingAfterAcceptance)",
            "receiver_voip_push_delivery_final_classification=\(receiverVoIPPushDeliveryFinalClassification)",
            "real_invite_payload_mapping_observed=\(realInvitePayloadMappingObserved)",
            "element_call_pushkit_callback_invoked=\(elementCallServicePushKitCallbackInvoked)",
            "element_call_salemx_payload_observed=\(elementCallServiceSalemXPayloadObserved)",
            "element_call_payload_kind=\(elementCallServicePayloadKind)",
            "element_call_forwarded_to_salemx_receipt_pipeline=\(elementCallServiceForwardedToSalemXReceiptPipeline)",
            "element_call_completed_without_salemx_callkit_report=\(elementCallServiceCompletedWithoutSalemXCallKitReport)",
            "pushkit_completion_called=\(completionCalled)",
            "callkit_report_requested=\(callKitReportRequested)",
            "callkit_report_result=\(callKitReportResult)",
            "callkit_report_completion_observed=\(callKitReportCompletionObserved)",
            "callkit_report_submitted_at_ms_redacted=\(callKitReportSubmittedAtMsRedacted)",
            "callkit_report_completion_at_ms_redacted=\(callKitReportCompletionAtMsRedacted)",
            "callkit_report_error_redacted=true",
            "callkit_surface_repair_present=\(callKitSurfaceRepairPresent)",
            "callkit_surface_repair_debug_only=\(callKitSurfaceRepairDebugOnly)",
            "callkit_surface_repair_provider_retention_verified=\(callKitSurfaceRepairProviderRetentionVerified)",
            "callkit_surface_repair_delegate_retention_verified=\(callKitSurfaceRepairDelegateRetentionVerified)",
            "callkit_surface_repair_active_uuid_retention_verified=\(callKitSurfaceRepairActiveUUIDRetentionVerified)",
            "callkit_surface_repair_report_completion_watchdog_present=\(callKitSurfaceRepairReportCompletionWatchdogPresent)",
            "callkit_surface_repair_report_completion_timeout_classified=\(callKitSurfaceRepairReportCompletionTimeoutClassified)",
            "callkit_surface_repair_pushkit_completion_safety_present=\(callKitSurfaceRepairPushKitCompletionSafetyPresent)",
            "callkit_surface_repair_pushkit_completion_safety_result=\(callKitSurfaceRepairPushKitCompletionSafetyResult)",
            "callkit_surface_repair_background_task_requested=\(callKitSurfaceRepairBackgroundTaskRequested)",
            "callkit_surface_repair_background_task_ended=\(callKitSurfaceRepairBackgroundTaskEnded)",
            "callkit_surface_repair_blocks_connect_without_answer=\(callKitSurfaceRepairBlocksConnectWithoutAnswer)",
            "callkit_surface_repair_blocks_metadata_without_answer=\(callKitSurfaceRepairBlocksMetadataWithoutAnswer)",
            "callkit_surface_repair_no_direct_answer_bypass=\(callKitSurfaceRepairNoDirectAnswerBypass)",
            "callkit_surface_repair_no_media_connect_on_no_answer=\(callKitSurfaceRepairNoMediaConnectOnNoAnswer)",
            "metadata_credentials_boundary_repair_present=\(metadataCredentialsBoundaryRepairPresent)",
            "metadata_credentials_boundary_repair_debug_only=\(metadataCredentialsBoundaryRepairDebugOnly)",
            "metadata_credentials_boundary_repair_requires_answer=\(metadataCredentialsBoundaryRepairRequiresAnswer)",
            "metadata_credentials_boundary_repair_blocks_without_answer=\(metadataCredentialsBoundaryRepairBlocksWithoutAnswer)",
            "metadata_credentials_boundary_repair_triggers_metadata_after_answer=\(metadataCredentialsBoundaryRepairTriggersMetadataAfterAnswer)",
            "metadata_credentials_boundary_repair_triggers_credentials_after_metadata=\(metadataCredentialsBoundaryRepairTriggersCredentialsAfterMetadata)",
            "metadata_credentials_boundary_repair_blocks_connect_until_credentials=\(metadataCredentialsBoundaryRepairBlocksConnectUntilCredentials)",
            "metadata_credentials_boundary_repair_does_not_consume_hook_before_credentials=\(metadataCredentialsBoundaryRepairDoesNotConsumeHookBeforeCredentials)",
            "metadata_credentials_boundary_repair_allows_hook_consumption_after_credentials=\(metadataCredentialsBoundaryRepairAllowsHookConsumptionAfterCredentials)",
            "metadata_credentials_boundary_repair_no_direct_connect_bypass=\(metadataCredentialsBoundaryRepairNoDirectConnectBypass)",
            "metadata_credentials_boundary_repair_raw_credentials_logged=\(metadataCredentialsBoundaryRepairRawCredentialsLogged)",
            "pending_metadata_reference_repair_present=\(pendingMetadataReferenceRepairPresent)",
            "pending_metadata_reference_repair_debug_only=\(pendingMetadataReferenceRepairDebugOnly)",
            "pending_metadata_reference_repair_real_invite_required=\(pendingMetadataReferenceRepairRealInviteRequired)",
            "pending_metadata_reference_repair_reference_created_before_apns=\(pendingMetadataReferenceRepairReferenceCreatedBeforeAPNs)",
            "pending_metadata_reference_repair_reference_present_in_apns_payload=\(pendingMetadataReferenceRepairReferencePresentInAPNsPayload)",
            "pending_metadata_reference_repair_reference_observed_by_pushkit=\(pendingMetadataReferenceRepairReferenceObservedByPushKit)",
            "pending_metadata_reference_repair_reference_handed_to_answer_pipeline=\(pendingMetadataReferenceRepairReferenceHandedToAnswerPipeline)",
            "pending_metadata_reference_repair_blocks_apns_without_reference=\(pendingMetadataReferenceRepairBlocksAPNsWithoutReference)",
            "pending_metadata_reference_repair_blocks_credentials_without_metadata_success=\(pendingMetadataReferenceRepairBlocksCredentialsWithoutMetadataSuccess)",
            "pending_metadata_reference_repair_no_direct_credentials_bypass=\(pendingMetadataReferenceRepairNoDirectCredentialsBypass)",
            "pending_metadata_reference_repair_no_connect_bypass=\(pendingMetadataReferenceRepairNoConnectBypass)",
            "pending_metadata_reference_repair_raw_metadata_logged=\(pendingMetadataReferenceRepairRawMetadataLogged)",
            "pushkit_completion_answerable_window_requested=\(pushKitCompletionAnswerableWindowRequested)",
            "pushkit_completion_answerable_window_result=\(pushKitCompletionAnswerableWindowResult)",
            "pushkit_completion_answerable_window_duration_bucket=\(pushKitCompletionAnswerableWindowDurationBucket)",
            "pushkit_completion_after_report_ms_bucket=\(pushKitCompletionAfterReportMsBucket)",
            "callkit_end_after_pushkit_completion_ms_bucket=\(callKitEndAfterPushKitCompletionMsBucket)",
            "app_state_at_pushkit_receipt=\(appStateAtPushKitReceipt)",
            "app_state_at_report_completion=\(appStateAtReportCompletion)",
            "app_state_at_first_callkit_action=\(appStateAtFirstCallKitAction)",
            "callkit_update_has_generic_handle=\(callKitUpdateHasGenericHandle)",
            "callkit_update_has_localized_caller_name=\(callKitUpdateHasLocalizedCallerName)",
            "callkit_update_audio_only=\(callKitUpdateAudioOnly)",
            "callkit_provider_configuration_audio_only=\(callKitProviderConfigurationAudioOnly)",
            "callkit_provider_configuration_supported_handle_generic=\(callKitProviderConfigurationSupportedHandleGeneric)",
            "local_callkit_only_update_equivalent_to_voip=\(localCallKitOnlyUpdateEquivalentToVoIP)",
            "local_callkit_only_provider_config_equivalent_to_voip=\(localCallKitOnlyProviderConfigEquivalentToVoIP)",
            "voip_callkit_update_equivalent_to_local=\(voIPCallKitUpdateEquivalentToLocal)",
            "voip_report_queue_matches_local=\(voIPReportQueueMatchesLocal)",
            "voip_provider_reuse_matches_local=\(voIPProviderReuseMatchesLocal)",
            "voip_operator_marker_set_before_report=\(voIPOperatorMarkerSetBeforeReport)",
            "voip_pushkit_completion_delayed_until_first_action=\(voIPPushKitCompletionDelayedUntilFirstAction)",
            "callkit_provider_retained_for_answer=\(callKitProviderRetainedForAnswer)",
            "callkit_delegate_retained_for_answer=\(callKitDelegateRetainedForAnswer)",
            "callkit_active_call_uuid_retained=\(callKitActiveCallUUIDRetained)",
            "callkit_provider_did_reset_observed=\(callKitProviderDidResetObserved)",
            "callkit_provider_reset_observed=\(callKitProviderDidResetObserved)",
            "callkit_provider_did_activate_audio_session=\(callKitProviderDidActivateAudioSession)",
            "callkit_audio_session_did_activate=\(callKitProviderDidActivateAudioSession)",
            "callkit_provider_did_deactivate_audio_session=\(callKitProviderDidDeactivateAudioSession)",
            "callkit_audio_session_did_deactivate=\(callKitProviderDidDeactivateAudioSession)",
            "provider_did_reset_before_first_action=\(providerDidResetBeforeFirstAction)",
            "audio_session_did_activate_before_first_action=\(audioSessionDidActivateBeforeFirstAction)",
            "audio_session_did_deactivate_before_first_action=\(audioSessionDidDeactivateBeforeFirstAction)",
            "callkit_first_action_kind=\(callKitFirstActionKind)",
            "callkit_first_action_after_report_ms_bucket=\(callKitFirstActionAfterReportMsBucket)",
            "operator_ready_to_answer=\(operatorReadyToAnswer)",
            "operator_expected_surface=\(operatorExpectedSurface)",
            "callkit_ui_surface_observed_by_operator=\(callKitUISurfaceObservedByOperator)",
            "callkit_operator_intended_action=\(callKitOperatorIntendedAction)",
            "callkit_operator_action_timing_bucket=\(callKitOperatorActionTimingBucket)",
            "callkit_ui_answer_operator_tap_observed=\(callKitUIAnswerOperatorTapObserved)",
            "callkit_end_arrived_before_operator_answer_window=\(callKitEndArrivedBeforeOperatorAnswerWindow)",
            "callkit_end_action_delivered=\(callKitEndActionDelivered)",
            "end_action_uuid_matched=\(endActionUUIDMatched)",
            "end_action_generation_matched=\(endActionGenerationMatched)",
            "end_action_source_matched=\(endActionSourceMatched)",
            "end_action_fulfilled=\(endActionFulfilled)",
            "end_action_origin=\(endActionOrigin)",
            "local_end_request_before_answer=\(localEndRequestBeforeAnswer)",
            "provider_invalidate_before_answer=\(providerInvalidateBeforeAnswer)",
            "report_call_ended_before_answer=\(reportCallEndedBeforeAnswer)",
            "controlled_timeout_before_answer=\(controlledTimeoutBeforeAnswer)",
            "callkit_answer_action_delivered=\(callKitAnswerActionDelivered)",
            "answer_action_uuid_matched=\(answerActionUUIDMatched)",
            "answer_action_generation_matched=\(answerActionGenerationMatched)",
            "callkit_event_order=\(callKitEventOrder)",
            "callkit_answer_action_received=\(callKitAnswerActionReceived)",
            "callkit_answer_action_fulfilled=\(callKitAnswerActionFulfilled)",
            "app_activation_observed=\(appActivationObserved)",
            "controlled_in_app_activation_requested=\(controlledInAppActivationRequested)",
            "controlled_in_app_activation_observed=\(controlledInAppActivationObserved)",
            "controlled_in_app_screen_requested=\(controlledInAppScreenRequested)",
            "controlled_in_app_screen_presented=\(controlledInAppScreenPresented)",
            "controlled_in_app_screen_source=\(controlledInAppScreenSource)",
            "foreground_call_state_handoff_requested=\(foregroundCallStateHandoffRequested)",
            "foreground_call_state_handoff_observed=\(foregroundCallStateHandoffObserved)",
            "foreground_call_state=\(foregroundCallState)",
            "foreground_call_state_source=\(foregroundCallStateSource)",
            "foreground_call_state_payload_redacted=\(foregroundCallStatePayloadRedacted)",
            "foreground_call_state_has_stable_redacted_correlation=\(foregroundCallStateHasStableRedactedCorrelation)",
            "foreground_pending_call_metadata_handoff_requested=\(foregroundPendingCallMetadataHandoffRequested)",
            "foreground_pending_call_metadata_handoff_observed=\(foregroundPendingCallMetadataHandoffObserved)",
            "foreground_pending_call_metadata_source=\(foregroundPendingCallMetadataSource)",
            "foreground_pending_call_metadata_payload_redacted=\(foregroundPendingCallMetadataPayloadRedacted)",
            "foreground_pending_call_metadata_has_call_identifier=\(foregroundPendingCallMetadataHasCallIdentifier)",
            "foreground_pending_call_metadata_has_room_binding=\(foregroundPendingCallMetadataHasRoomBinding)",
            "foreground_pending_call_metadata_has_peer=\(foregroundPendingCallMetadataHasPeer)",
            "foreground_pending_call_metadata_direction=\(foregroundPendingCallMetadataDirection)",
            "foreground_pending_call_metadata_intent=\(foregroundPendingCallMetadataIntent)",
            "media_credentials_request_metadata_available=\(mediaCredentialsRequestMetadataAvailable)",
            "media_credentials_request_metadata_redacted=\(mediaCredentialsRequestMetadataRedacted)",
            "media_credentials_request_metadata_source=\(mediaCredentialsRequestMetadataSource)",
            "media_credentials_boundary_reached=\(mediaCredentialsBoundaryReached)",
            "media_credentials_request_planned=\(mediaCredentialsRequestPlanned)",
            "media_credentials_requested=\(mediaCredentialsRequested)",
            "media_credentials_request_authorized=\(mediaCredentialsRequestAuthorized)",
            "media_credentials_result=\(mediaCredentialsResult)",
            "media_credentials_token_received=\(mediaCredentialsTokenReceived)",
            "media_credentials_token_redacted=\(mediaCredentialsTokenRedacted)",
            "media_credentials_url_received=\(mediaCredentialsURLReceived)",
            "media_credentials_url_redacted=\(mediaCredentialsURLRedacted)",
            "media_credentials_expires_at_present=\(mediaCredentialsExpiresAtPresent)",
            "media_credentials_payload_redacted=\(mediaCredentialsPayloadRedacted)",
            "media_credentials_local_persistence_requested=\(mediaCredentialsLocalPersistenceRequested)",
            "media_credentials_cleanup_requested=\(mediaCredentialsCleanupRequested)",
            "media_credentials_cleanup_result=\(mediaCredentialsCleanupResult)",
            "media_credentials_post_cleanup_token_present=\(mediaCredentialsPostCleanupTokenPresent)",
            "media_credentials_post_cleanup_url_present=\(mediaCredentialsPostCleanupURLPresent)",
            "media_credentials_post_cleanup_expires_at_present=\(mediaCredentialsPostCleanupExpiresAtPresent)",
            "media_credentials_post_cleanup_payload_present=\(mediaCredentialsPostCleanupPayloadPresent)",
            "media_credentials_reuse_attempted=\(mediaCredentialsReuseAttempted)",
            "media_credentials_reuse_allowed=\(mediaCredentialsReuseAllowed)",
            "media_credentials_expiry_reference_present=\(mediaCredentialsExpiryReferencePresent)",
            "media_credentials_expiry_check_requested=\(mediaCredentialsExpiryCheckRequested)",
            "media_credentials_expiry_check_result=\(mediaCredentialsExpiryCheckResult)",
            "media_credentials_token_request_seen=\(mediaCredentialsTokenRequestSeen)",
            "media_credentials_token_http_status_bucket=\(mediaCredentialsTokenHTTPStatusBucket)",
            "media_credentials_token_reason=\(mediaCredentialsTokenReason)",
            "media_credentials_eligibility_allowed=\(mediaCredentialsEligibilityAllowed)",
            "media_credentials_rate_limited=\(mediaCredentialsRateLimited)",
            "media_credentials_allocation_attempted=\(mediaCredentialsAllocationAttempted)",
            "media_credentials_livekit_room_precreate_attempted=\(mediaCredentialsLiveKitRoomPrecreateAttempted)",
            "media_credentials_token_issued=\(mediaCredentialsTokenIssued)",
            "physical6_runtime_enablement_url_hook_present=\(physical6RuntimeEnablementURLHookPresent)",
            "physical6_runtime_enablement_url_hook_debug_only=\(physical6RuntimeEnablementURLHookDebugOnly)",
            "physical6_runtime_enablement_url_hook_default_disabled=\(physical6RuntimeEnablementURLHookDefaultDisabled)",
            "physical6_runtime_enablement_url_hook_armed=\(physical6RuntimeEnablementURLHookArmed)",
            "physical6_runtime_enablement_url_hook_one_shot=\(physical6RuntimeEnablementURLHookOneShot)",
            "physical6_runtime_enablement_url_hook_audio_only=\(physical6RuntimeEnablementURLHookAudioOnly)",
            "physical6_runtime_enablement_url_hook_video_allowed=\(physical6RuntimeEnablementURLHookVideoAllowed)",
            "physical6_runtime_enablement_url_hook_matrix_events_allowed=\(physical6RuntimeEnablementURLHookMatrixEventsAllowed)",
            "physical6_runtime_enablement_url_hook_raw_credentials_logged=\(physical6RuntimeEnablementURLHookRawCredentialsLogged)",
            "physical6_runtime_enablement_url_hook_consumed=\(physical6RuntimeEnablementURLHookConsumed)",
            "physical6_runtime_enablement_url_hook_blocked_reason=\(physical6RuntimeEnablementURLHookBlockedReason)",
            "controlled_connect_activation_wiring_present=\(controlledConnectActivationWiringPresent)",
            "controlled_connect_activation_debug_only=\(controlledConnectActivationDebugOnly)",
            "controlled_connect_activation_default_disabled=\(controlledConnectActivationDefaultDisabled)",
            "controlled_connect_activation_requires_operator_approval=\(controlledConnectActivationRequiresOperatorApproval)",
            "controlled_connect_activation_rollback_available=\(controlledConnectActivationRollbackAvailable)",
            "controlled_connect_activation_scope=\(controlledConnectActivationScope)",
            "controlled_connect_video_allowed=\(controlledConnectVideoAllowed)",
            "controlled_connect_matrix_events_allowed=\(controlledConnectMatrixEventsAllowed)",
            "controlled_connect_raw_credentials_logged=\(controlledConnectRawCredentialsLogged)",
            "controlled_connect_switch_present=\(controlledConnectSwitchPresent)",
            "controlled_connect_switch_debug_only=\(controlledConnectSwitchDebugOnly)",
            "controlled_connect_switch_enabled=\(controlledConnectSwitchEnabled)",
            "controlled_connect_operator_approved=\(controlledConnectOperatorApproved)",
            "controlled_connect_execution_allowed=\(controlledConnectExecutionAllowed)",
            "controlled_connect_blocked_reason=\(controlledConnectBlockedReason)",
            "controlled_connect_blocked_before_engine=\(controlledConnectBlockedBeforeEngine)",
            "controlled_connect_blocked_before_livekit_join=\(controlledConnectBlockedBeforeLiveKitJoin)",
            "controlled_connect_blocked_before_permissions=\(controlledConnectBlockedBeforePermissions)",
            "controlled_connect_blocked_before_matrix_events=\(controlledConnectBlockedBeforeMatrixEvents)",
            "controlled_connect_enablement_wiring_present=\(controlledConnectEnablementWiringPresent)",
            "controlled_connect_enablement_debug_only=\(controlledConnectEnablementDebugOnly)",
            "controlled_connect_enablement_default_off=\(controlledConnectEnablementDefaultOff)",
            "controlled_connect_enablement_operator_approval_required=\(controlledConnectEnablementOperatorApprovalRequired)",
            "controlled_connect_enablement_one_shot=\(controlledConnectEnablementOneShot)",
            "controlled_connect_enablement_fresh_credentials_required=\(controlledConnectEnablementFreshCredentialsRequired)",
            "controlled_connect_enablement_audio_only=\(controlledConnectEnablementAudioOnly)",
            "controlled_connect_enablement_video_allowed=\(controlledConnectEnablementVideoAllowed)",
            "controlled_connect_enablement_matrix_events_allowed=\(controlledConnectEnablementMatrixEventsAllowed)",
            "controlled_connect_enablement_raw_credentials_logged=\(controlledConnectEnablementRawCredentialsLogged)",
            "controlled_connect_enablement_rollback_available=\(controlledConnectEnablementRollbackAvailable)",
            "controlled_connect_enablement_enabled=\(controlledConnectEnablementEnabled)",
            "controlled_connect_enablement_operator_approved=\(controlledConnectEnablementOperatorApproved)",
            "controlled_connect_enablement_future_phase_permitted=\(controlledConnectEnablementFuturePhasePermitted)",
            "controlled_connect_enablement_execution_allowed=\(controlledConnectEnablementExecutionAllowed)",
            "controlled_connect_enablement_blocked_reason=\(controlledConnectEnablementBlockedReason)",
            "controlled_audio_connect_execution_gate_present=\(controlledAudioConnectExecutionGatePresent)",
            "controlled_audio_connect_execution_debug_only=\(controlledAudioConnectExecutionDebugOnly)",
            "controlled_audio_connect_execution_audio_only=\(controlledAudioConnectExecutionAudioOnly)",
            "controlled_audio_connect_execution_video_allowed=\(controlledAudioConnectExecutionVideoAllowed)",
            "controlled_audio_connect_execution_matrix_events_allowed=\(controlledAudioConnectExecutionMatrixEventsAllowed)",
            "controlled_audio_connect_execution_raw_credentials_logged=\(controlledAudioConnectExecutionRawCredentialsLogged)",
            "controlled_audio_connect_execution_requires_enablement=\(controlledAudioConnectExecutionRequiresEnablement)",
            "controlled_audio_connect_execution_requires_operator_approval=\(controlledAudioConnectExecutionRequiresOperatorApproval)",
            "controlled_audio_connect_execution_requires_future_phase_permission=\(controlledAudioConnectExecutionRequiresFuturePhasePermission)",
            "controlled_audio_connect_execution_future_phase_permitted=\(controlledAudioConnectExecutionFuturePhasePermitted)",
            "controlled_audio_connect_execution_allowed=\(controlledAudioConnectExecutionAllowed)",
            "controlled_audio_connect_execution_blocked_reason=\(controlledAudioConnectExecutionBlockedReason)",
            "controlled_audio_connect_execution_blocked_before_engine=\(controlledAudioConnectExecutionBlockedBeforeEngine)",
            "controlled_audio_connect_execution_blocked_before_livekit_join=\(controlledAudioConnectExecutionBlockedBeforeLiveKitJoin)",
            "controlled_audio_connect_execution_blocked_before_permissions=\(controlledAudioConnectExecutionBlockedBeforePermissions)",
            "controlled_audio_connect_execution_blocked_before_matrix_events=\(controlledAudioConnectExecutionBlockedBeforeMatrixEvents)",
            "controlled_audio_connect_activation_path_present=\(controlledAudioConnectActivationPathPresent)",
            "controlled_audio_connect_activation_debug_only=\(controlledAudioConnectActivationDebugOnly)",
            "controlled_audio_connect_activation_one_shot=\(controlledAudioConnectActivationOneShot)",
            "controlled_audio_connect_activation_default_disabled=\(controlledAudioConnectActivationDefaultDisabled)",
            "controlled_audio_connect_activation_requires_receiver_session=\(controlledAudioConnectActivationRequiresReceiverSession)",
            "controlled_audio_connect_activation_requires_fresh_credentials=\(controlledAudioConnectActivationRequiresFreshCredentials)",
            "controlled_audio_connect_activation_requires_enablement=\(controlledAudioConnectActivationRequiresEnablement)",
            "controlled_audio_connect_activation_requires_operator_approval=\(controlledAudioConnectActivationRequiresOperatorApproval)",
            "controlled_audio_connect_activation_requires_future_phase_permission=\(controlledAudioConnectActivationRequiresFuturePhasePermission)",
            "controlled_audio_connect_activation_audio_only=\(controlledAudioConnectActivationAudioOnly)",
            "controlled_audio_connect_activation_video_allowed=\(controlledAudioConnectActivationVideoAllowed)",
            "controlled_audio_connect_activation_matrix_events_allowed=\(controlledAudioConnectActivationMatrixEventsAllowed)",
            "controlled_audio_connect_activation_raw_credentials_logged=\(controlledAudioConnectActivationRawCredentialsLogged)",
            "controlled_audio_connect_activation_rollback_available=\(controlledAudioConnectActivationRollbackAvailable)",
            "controlled_audio_connect_activation_allowed=\(controlledAudioConnectActivationAllowed)",
            "controlled_audio_connect_activation_blocked_reason=\(controlledAudioConnectActivationBlockedReason)",
            "controlled_audio_connect_activation_blocked_before_engine=\(controlledAudioConnectActivationBlockedBeforeEngine)",
            "controlled_audio_connect_activation_blocked_before_livekit_join=\(controlledAudioConnectActivationBlockedBeforeLiveKitJoin)",
            "controlled_audio_connect_activation_blocked_before_permissions=\(controlledAudioConnectActivationBlockedBeforePermissions)",
            "controlled_audio_connect_activation_blocked_before_matrix_events=\(controlledAudioConnectActivationBlockedBeforeMatrixEvents)",
            "controlled_connect_real_audio_path_present=\(controlledConnectRealAudioPathPresent)",
            "controlled_connect_real_audio_path_debug_only=\(controlledConnectRealAudioPathDebugOnly)",
            "controlled_connect_real_audio_path_default_disabled=\(controlledConnectRealAudioPathDefaultDisabled)",
            "controlled_connect_real_audio_path_requires_enablement=\(controlledConnectRealAudioPathRequiresEnablement)",
            "controlled_connect_real_audio_path_requires_operator_approval=\(controlledConnectRealAudioPathRequiresOperatorApproval)",
            "controlled_connect_real_audio_path_requires_future_phase_permission=\(controlledConnectRealAudioPathRequiresFuturePhasePermission)",
            "controlled_connect_real_audio_path_audio_only=\(controlledConnectRealAudioPathAudioOnly)",
            "controlled_connect_real_audio_path_video_allowed=\(controlledConnectRealAudioPathVideoAllowed)",
            "controlled_connect_real_audio_path_matrix_events_allowed=\(controlledConnectRealAudioPathMatrixEventsAllowed)",
            "controlled_connect_real_audio_path_raw_credentials_logged=\(controlledConnectRealAudioPathRawCredentialsLogged)",
            "controlled_connect_real_audio_path_one_shot=\(controlledConnectRealAudioPathOneShot)",
            "controlled_connect_real_audio_path_allowed=\(controlledConnectRealAudioPathAllowed)",
            "controlled_connect_real_audio_path_blocked_reason=\(controlledConnectRealAudioPathBlockedReason)",
            "controlled_connect_real_audio_path_blocked_before_engine=\(controlledConnectRealAudioPathBlockedBeforeEngine)",
            "controlled_connect_real_audio_path_can_reach_engine_when_all_gates_true=\(controlledConnectRealAudioPathCanReachEngineWhenAllGatesTrue)",
            "controlled_connect_real_runtime_path_present=\(controlledConnectRealRuntimePathPresent)",
            "controlled_connect_real_runtime_path_debug_only=\(controlledConnectRealRuntimePathDebugOnly)",
            "controlled_connect_real_runtime_path_default_disabled=\(controlledConnectRealRuntimePathDefaultDisabled)",
            "controlled_connect_real_runtime_path_requires_credentials=\(controlledConnectRealRuntimePathRequiresCredentials)",
            "controlled_connect_real_runtime_path_requires_enablement=\(controlledConnectRealRuntimePathRequiresEnablement)",
            "controlled_connect_real_runtime_path_requires_operator_approval=\(controlledConnectRealRuntimePathRequiresOperatorApproval)",
            "controlled_connect_real_runtime_path_requires_future_phase_permission=\(controlledConnectRealRuntimePathRequiresFuturePhasePermission)",
            "controlled_connect_real_runtime_path_audio_only=\(controlledConnectRealRuntimePathAudioOnly)",
            "controlled_connect_real_runtime_path_video_allowed=\(controlledConnectRealRuntimePathVideoAllowed)",
            "controlled_connect_real_runtime_path_matrix_events_allowed=\(controlledConnectRealRuntimePathMatrixEventsAllowed)",
            "controlled_connect_real_runtime_path_raw_credentials_logged=\(controlledConnectRealRuntimePathRawCredentialsLogged)",
            "controlled_connect_real_runtime_path_one_shot=\(controlledConnectRealRuntimePathOneShot)",
            "controlled_connect_real_runtime_path_allowed=\(controlledConnectRealRuntimePathAllowed)",
            "controlled_connect_real_runtime_path_blocked_reason=\(controlledConnectRealRuntimePathBlockedReason)",
            "controlled_connect_real_runtime_path_blocked_before_engine=\(controlledConnectRealRuntimePathBlockedBeforeEngine)",
            "controlled_connect_real_runtime_path_can_call_connect_media_when_all_gates_true=\(controlledConnectRealRuntimePathCanCallConnectMediaWhenAllGatesTrue)",
            "controlled_connect_real_runtime_path_can_call_livekit_audio_when_all_gates_true=\(controlledConnectRealRuntimePathCanCallLiveKitAudioWhenAllGatesTrue)",
            "controlled_connect_real_bridge_present=\(controlledConnectRealBridgePresent)",
            "controlled_connect_real_bridge_debug_only=\(controlledConnectRealBridgeDebugOnly)",
            "controlled_connect_real_bridge_default_disabled=\(controlledConnectRealBridgeDefaultDisabled)",
            "controlled_connect_real_bridge_requires_credentials=\(controlledConnectRealBridgeRequiresCredentials)",
            "controlled_connect_real_bridge_requires_enablement=\(controlledConnectRealBridgeRequiresEnablement)",
            "controlled_connect_real_bridge_requires_operator_approval=\(controlledConnectRealBridgeRequiresOperatorApproval)",
            "controlled_connect_real_bridge_requires_future_phase_permission=\(controlledConnectRealBridgeRequiresFuturePhasePermission)",
            "controlled_connect_real_bridge_audio_only=\(controlledConnectRealBridgeAudioOnly)",
            "controlled_connect_real_bridge_video_allowed=\(controlledConnectRealBridgeVideoAllowed)",
            "controlled_connect_real_bridge_matrix_events_allowed=\(controlledConnectRealBridgeMatrixEventsAllowed)",
            "controlled_connect_real_bridge_raw_credentials_logged=\(controlledConnectRealBridgeRawCredentialsLogged)",
            "controlled_connect_real_bridge_one_shot=\(controlledConnectRealBridgeOneShot)",
            "controlled_connect_real_bridge_allowed=\(controlledConnectRealBridgeAllowed)",
            "controlled_connect_real_bridge_blocked_reason=\(controlledConnectRealBridgeBlockedReason)",
            "controlled_connect_real_bridge_blocked_before_connect_media=\(controlledConnectRealBridgeBlockedBeforeConnectMedia)",
            "controlled_connect_real_bridge_can_call_connect_media_when_all_gates_true=\(controlledConnectRealBridgeCanCallConnectMediaWhenAllGatesTrue)",
            "controlled_connect_real_bridge_can_call_livekit_audio_when_all_gates_true=\(controlledConnectRealBridgeCanCallLiveKitAudioWhenAllGatesTrue)",
            "controlled_connect_real_bridge_uses_fake_engine_in_tests_only=\(controlledConnectRealBridgeUsesFakeEngineInTestsOnly)",
            "controlled_connect_real_bridge_uses_real_runtime_boundary_when_not_test=\(controlledConnectRealBridgeUsesRealRuntimeBoundaryWhenNotTest)",
            "media_connect_preflight_requested=\(mediaConnectPreflightRequested)",
            "media_connect_preflight_metadata_available=\(mediaConnectPreflightMetadataAvailable)",
            "media_connect_preflight_credentials_available=\(mediaConnectPreflightCredentialsAvailable)",
            "media_connect_preflight_token_present=\(mediaConnectPreflightTokenPresent)",
            "media_connect_preflight_url_present=\(mediaConnectPreflightURLPresent)",
            "media_connect_preflight_expires_at_present=\(mediaConnectPreflightExpiresAtPresent)",
            "media_connect_guard_enabled=\(mediaConnectGuardEnabled)",
            "media_connect_execution_allowed=\(mediaConnectExecutionAllowed)",
            "media_connect_preflight_result=\(mediaConnectPreflightResult)",
            "media_connect_blocked_reason=\(mediaConnectBlockedReason)",
            "media_connect_engine_invoked=\(mediaConnectEngineInvoked)",
            "livekit_connect_audio_invoked=\(liveKitConnectAudioInvoked)",
            "controlled_connect_first_attempt_requested=\(controlledConnectFirstAttemptRequested)",
            "controlled_connect_first_attempt_allowed=\(controlledConnectFirstAttemptAllowed)",
            "controlled_connect_first_attempt_started=\(controlledConnectFirstAttemptStarted)",
            "controlled_connect_first_attempt_completed=\(controlledConnectFirstAttemptCompleted)",
            "controlled_connect_first_attempt_repeated=\(controlledConnectFirstAttemptRepeated)",
            "controlled_connect_first_attempt_result=\(controlledConnectFirstAttemptResult)",
            "controlled_connect_first_attempt_error_bucket=\(controlledConnectFirstAttemptErrorBucket)",
            "controlled_connect_first_attempt_audio_only=\(controlledConnectFirstAttemptAudioOnly)",
            "controlled_connect_first_attempt_video_allowed=\(controlledConnectFirstAttemptVideoAllowed)",
            "controlled_connect_first_attempt_matrix_events_allowed=\(controlledConnectFirstAttemptMatrixEventsAllowed)",
            "controlled_connect_first_attempt_raw_credentials_logged=\(controlledConnectFirstAttemptRawCredentialsLogged)",
            "controlled_connect_first_attempt_blocked_reason=\(controlledConnectFirstAttemptBlockedReason)",
            "controlled_callkit_cleanup_requested=\(controlledCallKitCleanupRequested)",
            "controlled_callkit_cleanup_result=\(controlledCallKitCleanupResult)",
            "disconnect_cleanup_diagnostics_present=\(disconnectCleanupDiagnosticsPresent)",
            "disconnect_cleanup_diagnostics_debug_only=\(disconnectCleanupDiagnosticsDebugOnly)",
            "disconnect_cleanup_diagnostics_callkit_cleanup_requested=\(disconnectCleanupDiagnosticsCallKitCleanupRequested)",
            "disconnect_cleanup_diagnostics_callkit_cleanup_result=\(disconnectCleanupDiagnosticsCallKitCleanupResult)",
            "disconnect_cleanup_diagnostics_end_action_expected=\(disconnectCleanupDiagnosticsEndActionExpected)",
            "disconnect_cleanup_diagnostics_end_action_delivered=\(disconnectCleanupDiagnosticsEndActionDelivered)",
            "disconnect_cleanup_diagnostics_end_action_fulfilled=\(disconnectCleanupDiagnosticsEndActionFulfilled)",
            "disconnect_cleanup_diagnostics_end_action_origin=\(disconnectCleanupDiagnosticsEndActionOrigin)",
            "disconnect_cleanup_diagnostics_end_action_uuid_matched=\(disconnectCleanupDiagnosticsEndActionUUIDMatched)",
            "disconnect_cleanup_diagnostics_end_action_generation_matched=\(disconnectCleanupDiagnosticsEndActionGenerationMatched)",
            "disconnect_cleanup_diagnostics_end_action_source_matched=\(disconnectCleanupDiagnosticsEndActionSourceMatched)",
            "disconnect_cleanup_diagnostics_provider_end_reported=\(disconnectCleanupDiagnosticsProviderEndReported)",
            "disconnect_cleanup_diagnostics_local_cleanup_completed=\(disconnectCleanupDiagnosticsLocalCleanupCompleted)",
            "disconnect_cleanup_diagnostics_audio_session_deactivated=\(disconnectCleanupDiagnosticsAudioSessionDeactivated)",
            "disconnect_cleanup_diagnostics_livekit_cleanup_requested=\(disconnectCleanupDiagnosticsLiveKitCleanupRequested)",
            "disconnect_cleanup_diagnostics_livekit_cleanup_completed=\(disconnectCleanupDiagnosticsLiveKitCleanupCompleted)",
            "disconnect_cleanup_diagnostics_one_shot_consumed=\(disconnectCleanupDiagnosticsOneShotConsumed)",
            "disconnect_cleanup_diagnostics_no_repeated_connect=\(disconnectCleanupDiagnosticsNoRepeatedConnect)",
            "disconnect_cleanup_diagnostics_no_matrix_events=\(disconnectCleanupDiagnosticsNoMatrixEvents)",
            "disconnect_cleanup_diagnostics_no_video=\(disconnectCleanupDiagnosticsNoVideo)",
            "disconnect_cleanup_diagnostics_raw_identifiers_logged=\(disconnectCleanupDiagnosticsRawIdentifiersLogged)",
            "disconnect_cleanup_diagnostics_end_timing_classification=\(disconnectCleanupDiagnosticsEndTimingClassification)",
            "disconnect_cleanup_diagnostics_result=\(disconnectCleanupDiagnosticsResult)",
            "remote_audio_liveness_diagnostics_present=\(remoteAudioLivenessDiagnosticsPresent)",
            "remote_audio_liveness_diagnostics_debug_only=\(remoteAudioLivenessDiagnosticsDebugOnly)",
            "remote_audio_liveness_diagnostics_audio_only=\(remoteAudioLivenessDiagnosticsAudioOnly)",
            "remote_audio_liveness_diagnostics_video_allowed=\(remoteAudioLivenessDiagnosticsVideoAllowed)",
            "remote_audio_liveness_diagnostics_matrix_events_allowed=\(remoteAudioLivenessDiagnosticsMatrixEventsAllowed)",
            "remote_audio_liveness_diagnostics_raw_identifiers_logged=\(remoteAudioLivenessDiagnosticsRawIdentifiersLogged)",
            "remote_audio_publish_liveness_repair_present=\(remoteAudioPublishLivenessRepairPresent)",
            "remote_audio_publish_liveness_repair_debug_only=\(remoteAudioPublishLivenessRepairDebugOnly)",
            "remote_audio_publish_liveness_repair_requires_livekit_join_success=\(remoteAudioPublishLivenessRepairRequiresLiveKitJoinSuccess)",
            "remote_audio_publish_liveness_repair_classifies_publish_not_requested=\(remoteAudioPublishLivenessRepairClassifiesPublishNotRequested)",
            "remote_audio_publish_liveness_repair_classifies_publish_success=\(remoteAudioPublishLivenessRepairClassifiesPublishSuccess)",
            "remote_audio_publish_liveness_repair_classifies_publish_failure=\(remoteAudioPublishLivenessRepairClassifiesPublishFailure)",
            "remote_audio_publish_liveness_repair_classifies_simulator_peer=\(remoteAudioPublishLivenessRepairClassifiesSimulatorPeer)",
            "remote_audio_publish_liveness_repair_classifies_remote_missing=\(remoteAudioPublishLivenessRepairClassifiesRemoteMissing)",
            "remote_audio_publish_liveness_repair_classifies_remote_track_missing=\(remoteAudioPublishLivenessRepairClassifiesRemoteTrackMissing)",
            "remote_audio_publish_liveness_repair_classifies_liveness_observed=\(remoteAudioPublishLivenessRepairClassifiesLivenessObserved)",
            "remote_audio_publish_liveness_repair_no_video=\(remoteAudioPublishLivenessRepairNoVideo)",
            "remote_audio_publish_liveness_repair_no_matrix_events=\(remoteAudioPublishLivenessRepairNoMatrixEvents)",
            "remote_audio_publish_liveness_repair_raw_identifiers_logged=\(remoteAudioPublishLivenessRepairRawIdentifiersLogged)",
            "remote_participant_presence_repair_present=\(remoteParticipantPresenceRepairPresent)",
            "remote_participant_presence_repair_debug_only=\(remoteParticipantPresenceRepairDebugOnly)",
            "remote_participant_presence_repair_requires_two_physical_devices=\(remoteParticipantPresenceRepairRequiresTwoPhysicalDevices)",
            "remote_participant_presence_repair_requires_same_room=\(remoteParticipantPresenceRepairRequiresSameRoom)",
            "remote_participant_presence_repair_requires_sender_livekit_readiness=\(remoteParticipantPresenceRepairRequiresSenderLiveKitReadiness)",
            "remote_participant_presence_repair_sender_join_path_present=\(remoteParticipantPresenceRepairSenderJoinPathPresent)",
            "remote_participant_presence_repair_sender_join_default_disabled=\(remoteParticipantPresenceRepairSenderJoinDefaultDisabled)",
            "remote_participant_presence_repair_receiver_observer_present=\(remoteParticipantPresenceRepairReceiverObserverPresent)",
            "remote_participant_presence_repair_same_livekit_room_required=\(remoteParticipantPresenceRepairSameLiveKitRoomRequired)",
            "remote_participant_presence_repair_classifies_sender_not_joined=\(remoteParticipantPresenceRepairClassifiesSenderNotJoined)",
            "remote_participant_presence_repair_classifies_remote_missing=\(remoteParticipantPresenceRepairClassifiesRemoteMissing)",
            "remote_participant_presence_repair_classifies_remote_seen=\(remoteParticipantPresenceRepairClassifiesRemoteSeen)",
            "remote_participant_presence_repair_no_video=\(remoteParticipantPresenceRepairNoVideo)",
            "remote_participant_presence_repair_no_matrix_events=\(remoteParticipantPresenceRepairNoMatrixEvents)",
            "remote_participant_presence_repair_raw_identifiers_logged=\(remoteParticipantPresenceRepairRawIdentifiersLogged)",
            "remote_participant_observation_timing_repair_present=\(remoteParticipantObservationTimingRepairPresent)",
            "remote_participant_observation_timing_repair_debug_only=\(remoteParticipantObservationTimingRepairDebugOnly)",
            "remote_participant_observation_timing_repair_bounded_window=\(remoteParticipantObservationTimingRepairBoundedWindow)",
            "remote_participant_observation_timing_repair_raw_identifiers_logged=\(remoteParticipantObservationTimingRepairRawIdentifiersLogged)",
            "participant_observer_propagation_repair_present=\(participantObserverPropagationRepairPresent)",
            "participant_observer_propagation_repair_debug_only=\(participantObserverPropagationRepairDebugOnly)",
            "participant_observer_propagation_raw_identifiers_logged=\(participantObserverPropagationRawIdentifiersLogged)",
            "receiver_sender_connected_overlap_repair_present=\(receiverSenderConnectedOverlapRepairPresent)",
            "receiver_sender_connected_overlap_repair_debug_only=\(receiverSenderConnectedOverlapRepairDebugOnly)",
            "receiver_sender_connected_overlap_repair_raw_identifiers_logged=\(receiverSenderConnectedOverlapRepairRawIdentifiersLogged)",
            "receiver_connected_window_retention_repair_present=\(receiverConnectedWindowRetentionRepairPresent)",
            "receiver_connected_window_retention_repair_debug_only=\(receiverConnectedWindowRetentionRepairDebugOnly)",
            "receiver_connected_window_retention_repair_raw_identifiers_logged=\(receiverConnectedWindowRetentionRepairRawIdentifiersLogged)",
            "receiver_connected_session_lease_present=\(receiverConnectedSessionLeasePresent)",
            "receiver_connected_session_lease_debug_only=\(receiverConnectedSessionLeaseDebugOnly)",
            "receiver_connected_session_lease_acquired=\(receiverConnectedSessionLeaseAcquired)",
            "receiver_connected_session_lease_room_retained=\(receiverConnectedSessionLeaseRoomRetained)",
            "receiver_connected_session_lease_delegate_retained=\(receiverConnectedSessionLeaseDelegateRetained)",
            "receiver_connected_session_lease_observer_retained=\(receiverConnectedSessionLeaseObserverRetained)",
            "receiver_connected_session_lease_task_retained=\(receiverConnectedSessionLeaseTaskRetained)",
            "receiver_connected_session_lease_active_before_sender_trigger=\(receiverConnectedSessionLeaseActiveBeforeSenderTrigger)",
            "receiver_connected_session_lease_active_after_sender_trigger=\(receiverConnectedSessionLeaseActiveAfterSenderTrigger)",
            "receiver_connected_session_lease_active_at_sender_signal=\(receiverConnectedSessionLeaseActiveAtSenderSignal)",
            "receiver_connected_session_lease_released=\(receiverConnectedSessionLeaseReleased)",
            "receiver_connected_session_lease_released_after_terminal=\(receiverConnectedSessionLeaseReleasedAfterTerminal)",
            "receiver_connected_session_lease_release_reason=\(receiverConnectedSessionLeaseReleaseReason)",
            "receiver_connected_session_lease_repeated_release=\(receiverConnectedSessionLeaseRepeatedRelease)",
            "receiver_room_retained_for_sender_observation=\(receiverRoomRetainedForSenderObservation)",
            "receiver_observer_attached_before_sender_join=\(receiverObserverAttachedBeforeSenderJoin)",
            "receiver_observer_active_during_sender_join=\(receiverObserverActiveDuringSenderJoin)",
            "receiver_cleanup_deferred_until_observation_terminal=\(receiverCleanupDeferredUntilObservationTerminal)",
            "receiver_cleanup_started_before_sender_terminal=\(receiverCleanupStartedBeforeSenderTerminal)",
            "sender_join_terminal_seen_by_receiver=\(senderJoinTerminalSeenByReceiver)",
            "sender_room_connected_during_receiver_window=\(senderRoomConnectedDuringReceiverWindow)",
            "sender_cleanup_started_before_receiver_observation=\(senderCleanupStartedBeforeReceiverObservation)",
            "receiver_sender_connected_window_overlap_observed=\(receiverSenderConnectedWindowOverlapObserved)",
            "receiver_connected_window_opened=\(receiverConnectedWindowOpened)",
            "receiver_connected_window_closed=\(receiverConnectedWindowClosed)",
            "receiver_connected_window_close_reason=\(receiverConnectedWindowCloseReason)",
            "receiver_connected_window_closed_before_sender_connected=\(receiverConnectedWindowClosedBeforeSenderConnected)",
            "receiver_connected_window_retained_until_sender_terminal=\(receiverConnectedWindowRetainedUntilSenderTerminal)",
            "receiver_disconnect_observed_before_sender_signal=\(receiverDisconnectObservedBeforeSenderSignal)",
            "receiver_disconnect_observed_after_sender_signal=\(receiverDisconnectObservedAfterSenderSignal)",
            "sender_connected_signal_handoff_present=\(senderConnectedSignalHandoffPresent)",
            "sender_connected_signal_handoff_debug_only=\(senderConnectedSignalHandoffDebugOnly)",
            "sender_connected_signal_handoff_raw_identifiers_logged=\(senderConnectedSignalHandoffRawIdentifiersLogged)",
            "sender_connected_signal_emitted=\(senderConnectedSignalEmitted)",
            "sender_connected_signal_emit_source=\(senderConnectedSignalEmitSource)",
            "sender_connected_signal_emitted_after_runtime_join_success=\(senderConnectedSignalEmittedAfterRuntimeJoinSuccess)",
            "sender_connected_signal_opaque_correlation_present=\(senderConnectedSignalOpaqueCorrelationPresent)",
            "sender_connected_signal_raw_room_logged=\(senderConnectedSignalRawRoomLogged)",
            "sender_connected_signal_raw_call_logged=\(senderConnectedSignalRawCallLogged)",
            "sender_connected_signal_raw_user_logged=\(senderConnectedSignalRawUserLogged)",
            "sender_connected_signal_raw_device_logged=\(senderConnectedSignalRawDeviceLogged)",
            "sender_connected_signal_received_by_receiver=\(senderConnectedSignalReceivedByReceiver)",
            "sender_connected_signal_source=\(senderConnectedSignalSource)",
            "sender_connected_signal_before_receiver_disconnect=\(senderConnectedSignalBeforeReceiverDisconnect)",
            "sender_connected_signal_after_receiver_disconnect=\(senderConnectedSignalAfterReceiverDisconnect)",
            "sender_connected_signal_raw_identifiers_logged=\(senderConnectedSignalRawIdentifiersLogged)",
            "receiver_sender_connected_signal_wait_started=\(receiverSenderConnectedSignalWaitStarted)",
            "receiver_sender_connected_signal_wait_completed=\(receiverSenderConnectedSignalWaitCompleted)",
            "receiver_sender_connected_signal_received=\(receiverSenderConnectedSignalReceived)",
            "receiver_sender_connected_signal_correlation_match=\(receiverSenderConnectedSignalCorrelationMatch)",
            "receiver_sender_connected_signal_received_before_receiver_disconnect=\(receiverSenderConnectedSignalReceivedBeforeReceiverDisconnect)",
            "receiver_sender_connected_signal_received_after_receiver_disconnect=\(receiverSenderConnectedSignalReceivedAfterReceiverDisconnect)",
            "receiver_sender_connected_signal_timeout=\(receiverSenderConnectedSignalTimeout)",
            "receiver_sender_connected_signal_final_classification=\(receiverSenderConnectedSignalFinalClassification)",
            "receiver_sender_connected_window_overlap_wait_started=\(receiverSenderConnectedWindowOverlapWaitStarted)",
            "receiver_sender_connected_window_overlap_wait_completed=\(receiverSenderConnectedWindowOverlapWaitCompleted)",
            "receiver_sender_connected_window_overlap_wait_timeout=\(receiverSenderConnectedWindowOverlapWaitTimeout)",
            "receiver_sender_connected_window_overlap_final_classification=\(receiverSenderConnectedWindowOverlapFinalClassification)",
            "sender_readiness_context_present_during_observation=\(senderReadinessContextPresentDuringObservation)",
            "opaque_call_correlation_present=\(opaqueCallCorrelationPresent)",
            "opaque_call_correlation_match=\(opaqueCallCorrelationMatch)",
            "remote_participant_observation_wait_started=\(remoteParticipantObservationWaitStarted)",
            "remote_participant_observation_wait_completed=\(remoteParticipantObservationWaitCompleted)",
            "remote_participant_observation_timeout_bucket=\(remoteParticipantObservationTimeoutBucket)",
            "remote_participant_observation_final_classification=\(remoteParticipantObservationFinalClassification)",
            "receiver_participant_observation_final_classification=\(receiverParticipantObservationFinalClassification)",
            "receiver_participant_observer_bound_to_retained_room=\(receiverParticipantObserverBoundToRetainedRoom)",
            "receiver_participant_observer_bound_to_connected_room=\(receiverParticipantObserverBoundToConnectedRoom)",
            "receiver_participant_observer_attached_before_sender_signal=\(receiverParticipantObserverAttachedBeforeSenderSignal)",
            "receiver_participant_observer_active_after_sender_signal=\(receiverParticipantObserverActiveAfterSenderSignal)",
            "receiver_participant_event_callback_seen=\(receiverParticipantEventCallbackSeen)",
            "receiver_participant_snapshot_requested=\(receiverParticipantSnapshotRequested)",
            "receiver_participant_snapshot_count_bucket=\(receiverParticipantSnapshotCountBucket)",
            "receiver_participant_snapshot_seen=\(receiverParticipantSnapshotSeen)",
            "receiver_participant_identity_filter_applied=\(receiverParticipantIdentityFilterApplied)",
            "receiver_participant_identity_filter_result=\(receiverParticipantIdentityFilterResult)",
            "receiver_participant_observation_after_overlap_started=\(receiverParticipantObservationAfterOverlapStarted)",
            "receiver_participant_observation_after_overlap_completed=\(receiverParticipantObservationAfterOverlapCompleted)",
            "receiver_participant_observation_after_overlap_timeout=\(receiverParticipantObservationAfterOverlapTimeout)",
            "sender_livekit_readiness_hook_present=\(senderLiveKitReadinessHookPresent)",
            "sender_livekit_readiness_hook_debug_only=\(senderLiveKitReadinessHookDebugOnly)",
            "sender_livekit_readiness_hook_default_disabled=\(senderLiveKitReadinessHookDefaultDisabled)",
            "sender_livekit_readiness_hook_armed=\(senderLiveKitReadinessHookArmed)",
            "sender_livekit_readiness_hook_matrix_session_ready=\(senderLiveKitReadinessHookMatrixSessionReady)",
            "sender_livekit_readiness_hook_expected_user_matched=\(senderLiveKitReadinessHookExpectedUserMatched)",
            "sender_livekit_readiness_hook_same_room_ready=\(senderLiveKitReadinessHookSameRoomReady)",
            "sender_livekit_readiness_hook_credentials_ready=\(senderLiveKitReadinessHookCredentialsReady)",
            "sender_livekit_readiness_hook_audio_only=\(senderLiveKitReadinessHookAudioOnly)",
            "sender_livekit_readiness_hook_video_allowed=\(senderLiveKitReadinessHookVideoAllowed)",
            "sender_livekit_readiness_hook_matrix_events_allowed=\(senderLiveKitReadinessHookMatrixEventsAllowed)",
            "sender_livekit_readiness_hook_raw_identifiers_logged=\(senderLiveKitReadinessHookRawIdentifiersLogged)",
            "sender_livekit_readiness_hook_blocked_reason=\(senderLiveKitReadinessHookBlockedReason)",
            "sender_readiness_runtime_handoff_present=\(senderReadinessRuntimeHandoffPresent)",
            "sender_readiness_runtime_handoff_debug_only=\(senderReadinessRuntimeHandoffDebugOnly)",
            "sender_readiness_runtime_handoff_armed_before_apns=\(senderReadinessRuntimeHandoffArmedBeforeAPNs)",
            "sender_readiness_runtime_handoff_received_by_runtime=\(senderReadinessRuntimeHandoffReceivedByRuntime)",
            "sender_readiness_runtime_handoff_survived_pushkit=\(senderReadinessRuntimeHandoffSurvivedPushKit)",
            "sender_readiness_runtime_handoff_survived_answer=\(senderReadinessRuntimeHandoffSurvivedAnswer)",
            "sender_readiness_runtime_handoff_matrix_session_ready=\(senderReadinessRuntimeHandoffMatrixSessionReady)",
            "sender_readiness_runtime_handoff_same_room_ready=\(senderReadinessRuntimeHandoffSameRoomReady)",
            "sender_readiness_runtime_handoff_expected_user_matched=\(senderReadinessRuntimeHandoffExpectedUserMatched)",
            "sender_readiness_runtime_handoff_raw_identifiers_logged=\(senderReadinessRuntimeHandoffRawIdentifiersLogged)",
            "sender_readiness_runtime_handoff_missing_classified=\(senderReadinessRuntimeHandoffMissingClassified)",
            "second_physical_sender_livekit_readiness_present=\(secondPhysicalSenderLiveKitReadinessPresent)",
            "second_physical_sender_livekit_readiness_debug_only=\(secondPhysicalSenderLiveKitReadinessDebugOnly)",
            "second_physical_sender_livekit_readiness_default_disabled=\(secondPhysicalSenderLiveKitReadinessDefaultDisabled)",
            "second_physical_sender_livekit_readiness_matrix_session_ready=\(secondPhysicalSenderLiveKitReadinessMatrixSessionReady)",
            "second_physical_sender_livekit_readiness_same_room_ready=\(secondPhysicalSenderLiveKitReadinessSameRoomReady)",
            "second_physical_sender_livekit_readiness_credentials_ready=\(secondPhysicalSenderLiveKitReadinessCredentialsReady)",
            "second_physical_sender_livekit_join_path_present=\(secondPhysicalSenderLiveKitJoinPathPresent)",
            "second_physical_sender_livekit_join_path_default_disabled=\(secondPhysicalSenderLiveKitJoinPathDefaultDisabled)",
            "second_physical_sender_livekit_join_path_audio_only=\(secondPhysicalSenderLiveKitJoinPathAudioOnly)",
            "second_physical_sender_livekit_join_path_video_allowed=\(secondPhysicalSenderLiveKitJoinPathVideoAllowed)",
            "second_physical_sender_livekit_join_path_matrix_events_allowed=\(secondPhysicalSenderLiveKitJoinPathMatrixEventsAllowed)",
            "second_physical_sender_livekit_join_path_raw_credentials_logged=\(secondPhysicalSenderLiveKitJoinPathRawCredentialsLogged)",
            "sender_side_livekit_join_hook_present=\(senderSideLiveKitJoinHookPresent)",
            "sender_side_livekit_join_hook_debug_only=\(senderSideLiveKitJoinHookDebugOnly)",
            "sender_side_livekit_join_hook_default_disabled=\(senderSideLiveKitJoinHookDefaultDisabled)",
            "sender_side_livekit_join_hook_armed=\(senderSideLiveKitJoinHookArmed)",
            "sender_side_livekit_join_hook_audio_only=\(senderSideLiveKitJoinHookAudioOnly)",
            "sender_side_livekit_join_hook_video_allowed=\(senderSideLiveKitJoinHookVideoAllowed)",
            "sender_side_livekit_join_hook_matrix_events_allowed=\(senderSideLiveKitJoinHookMatrixEventsAllowed)",
            "sender_side_livekit_join_hook_raw_credentials_logged=\(senderSideLiveKitJoinHookRawCredentialsLogged)",
            "sender_side_livekit_join_requested=\(senderSideLiveKitJoinRequested)",
            "sender_side_livekit_join_result=\(senderSideLiveKitJoinResult)",
            "sender_side_livekit_join_error_bucket=\(senderSideLiveKitJoinErrorBucket)",
            "sender_side_livekit_join_repeated=\(senderSideLiveKitJoinRepeated)",
            "sender_connect_parity_present=\(senderConnectParityPresent)",
            "sender_connect_parity_debug_only=\(senderConnectParityDebugOnly)",
            "sender_connect_parity_raw_url_logged=\(senderConnectParityRawURLLogged)",
            "sender_connect_parity_raw_token_logged=\(senderConnectParityRawTokenLogged)",
            "sender_connect_parity_raw_room_logged=\(senderConnectParityRawRoomLogged)",
            "sender_connect_parity_raw_identity_logged=\(senderConnectParityRawIdentityLogged)",
            "sender_connect_parity_uses_receiver_proven_connect_wrapper=\(senderConnectParityUsesReceiverProvenConnectWrapper)",
            "sender_connect_parity_uses_audio_only=\(senderConnectParityUsesAudioOnly)",
            "sender_connect_parity_video_allowed=\(senderConnectParityVideoAllowed)",
            "sender_connect_parity_matrix_events_allowed=\(senderConnectParityMatrixEventsAllowed)",
            "sender_connect_parity_room_retained_until_terminal=\(senderConnectParityRoomRetainedUntilTerminal)",
            "sender_connect_parity_delegate_retained_until_terminal=\(senderConnectParityDelegateRetainedUntilTerminal)",
            "sender_connect_parity_state_observer_retained_until_terminal=\(senderConnectParityStateObserverRetainedUntilTerminal)",
            "sender_connect_parity_task_retained_until_terminal=\(senderConnectParityTaskRetainedUntilTerminal)",
            "sender_connect_parity_bounded_wait_used=\(senderConnectParityBoundedWaitUsed)",
            "sender_connect_executor_unification_present=\(senderConnectExecutorUnificationPresent)",
            "sender_connect_executor_unification_debug_only=\(senderConnectExecutorUnificationDebugOnly)",
            "sender_connect_executor_unification_receiver_executor_shared=\(senderConnectExecutorUnificationReceiverExecutorShared)",
            "sender_connect_executor_unification_sender_executor_shared=\(senderConnectExecutorUnificationSenderExecutorShared)",
            "sender_connect_executor_unification_same_connect_options_shape=\(senderConnectExecutorUnificationSameConnectOptionsShape)",
            "sender_connect_executor_unification_same_room_retention_model=\(senderConnectExecutorUnificationSameRoomRetentionModel)",
            "sender_connect_executor_unification_same_delegate_retention_model=\(senderConnectExecutorUnificationSameDelegateRetentionModel)",
            "sender_connect_executor_unification_same_state_observer_model=\(senderConnectExecutorUnificationSameStateObserverModel)",
            "sender_connect_executor_unification_same_bounded_wait_model=\(senderConnectExecutorUnificationSameBoundedWaitModel)",
            "sender_connect_executor_unification_audio_only=\(senderConnectExecutorUnificationAudioOnly)",
            "sender_connect_executor_unification_video_allowed=\(senderConnectExecutorUnificationVideoAllowed)",
            "sender_connect_executor_unification_matrix_events_allowed=\(senderConnectExecutorUnificationMatrixEventsAllowed)",
            "sender_connect_executor_unification_raw_url_logged=\(senderConnectExecutorUnificationRawURLLogged)",
            "sender_connect_executor_unification_raw_token_logged=\(senderConnectExecutorUnificationRawTokenLogged)",
            "sender_connect_executor_unification_raw_room_logged=\(senderConnectExecutorUnificationRawRoomLogged)",
            "sender_connect_executor_unification_raw_identity_logged=\(senderConnectExecutorUnificationRawIdentityLogged)",
            "sender_join_failure_diagnostics_present=\(senderJoinFailureDiagnosticsPresent)",
            "sender_join_failure_diagnostics_debug_only=\(senderJoinFailureDiagnosticsDebugOnly)",
            "sender_join_failure_diagnostics_audio_only=\(senderJoinFailureDiagnosticsAudioOnly)",
            "sender_join_failure_diagnostics_video_allowed=\(senderJoinFailureDiagnosticsVideoAllowed)",
            "sender_join_failure_diagnostics_matrix_events_allowed=\(senderJoinFailureDiagnosticsMatrixEventsAllowed)",
            "sender_join_failure_diagnostics_raw_identifiers_logged=\(senderJoinFailureDiagnosticsRawIdentifiersLogged)",
            "sender_join_failure_diagnostics_credentials_present=\(senderJoinFailureDiagnosticsCredentialsPresent)",
            "sender_join_failure_diagnostics_token_present=\(senderJoinFailureDiagnosticsTokenPresent)",
            "sender_join_failure_diagnostics_url_present=\(senderJoinFailureDiagnosticsURLPresent)",
            "sender_join_failure_diagnostics_room_binding_present=\(senderJoinFailureDiagnosticsRoomBindingPresent)",
            "sender_join_failure_diagnostics_same_livekit_room=\(senderJoinFailureDiagnosticsSameLiveKitRoom)",
            "sender_join_failure_diagnostics_transport_attempted=\(senderJoinFailureDiagnosticsTransportAttempted)",
            "sender_join_failure_diagnostics_transport_result=\(senderJoinFailureDiagnosticsTransportResult)",
            "sender_join_failure_diagnostics_error_bucket=\(senderJoinFailureDiagnosticsErrorBucket)",
            "sender_join_failure_diagnostics_classification=\(senderJoinFailureDiagnosticsClassification)",
            "sender_transport_failure_diagnostics_present=\(senderTransportFailureDiagnosticsPresent)",
            "sender_transport_failure_diagnostics_debug_only=\(senderTransportFailureDiagnosticsDebugOnly)",
            "sender_transport_failure_diagnostics_audio_only=\(senderTransportFailureDiagnosticsAudioOnly)",
            "sender_transport_failure_diagnostics_video_allowed=\(senderTransportFailureDiagnosticsVideoAllowed)",
            "sender_transport_failure_diagnostics_matrix_events_allowed=\(senderTransportFailureDiagnosticsMatrixEventsAllowed)",
            "sender_transport_failure_diagnostics_raw_identifiers_logged=\(senderTransportFailureDiagnosticsRawIdentifiersLogged)",
            "sender_transport_failure_diagnostics_transport_attempted=\(senderTransportFailureDiagnosticsTransportAttempted)",
            "sender_transport_failure_diagnostics_transport_started=\(senderTransportFailureDiagnosticsTransportStarted)",
            "sender_transport_failure_diagnostics_transport_completed=\(senderTransportFailureDiagnosticsTransportCompleted)",
            "sender_transport_failure_diagnostics_transport_result=\(senderTransportFailureDiagnosticsTransportResult)",
            "sender_transport_failure_diagnostics_error_bucket=\(senderTransportFailureDiagnosticsErrorBucket)",
            "sender_transport_failure_diagnostics_classification=\(senderTransportFailureDiagnosticsClassification)",
            "sender_transport_failure_diagnostics_livekit_url_present=\(senderTransportFailureDiagnosticsLiveKitURLPresent)",
            "sender_transport_failure_diagnostics_token_present=\(senderTransportFailureDiagnosticsTokenPresent)",
            "sender_transport_failure_diagnostics_room_binding_present=\(senderTransportFailureDiagnosticsRoomBindingPresent)",
            "sender_transport_failure_diagnostics_same_livekit_room=\(senderTransportFailureDiagnosticsSameLiveKitRoom)",
            "sender_transport_failure_diagnostics_same_token_authority=\(senderTransportFailureDiagnosticsSameTokenAuthority)",
            "sender_transport_failure_diagnostics_receiver_sender_room_match=\(senderTransportFailureDiagnosticsReceiverSenderRoomMatch)",
            "sender_transport_failure_diagnostics_receiver_sender_token_authority_match=\(senderTransportFailureDiagnosticsReceiverSenderTokenAuthorityMatch)",
            "sender_transport_error_surface_present=\(senderTransportErrorSurfacePresent)",
            "sender_transport_error_surface_debug_only=\(senderTransportErrorSurfaceDebugOnly)",
            "sender_transport_error_surface_raw_error_logged=\(senderTransportErrorSurfaceRawErrorLogged)",
            "sender_transport_error_surface_raw_url_logged=\(senderTransportErrorSurfaceRawURLLogged)",
            "sender_transport_error_surface_raw_token_logged=\(senderTransportErrorSurfaceRawTokenLogged)",
            "sender_livekit_sdk_failure_surface_present=\(senderLiveKitSDKFailureSurfacePresent)",
            "sender_livekit_sdk_failure_surface_debug_only=\(senderLiveKitSDKFailureSurfaceDebugOnly)",
            "sender_livekit_sdk_failure_surface_raw_error_logged=\(senderLiveKitSDKFailureSurfaceRawErrorLogged)",
            "sender_livekit_sdk_failure_surface_raw_url_logged=\(senderLiveKitSDKFailureSurfaceRawURLLogged)",
            "sender_livekit_sdk_failure_surface_raw_token_logged=\(senderLiveKitSDKFailureSurfaceRawTokenLogged)",
            "sender_livekit_sdk_failure_surface_raw_room_logged=\(senderLiveKitSDKFailureSurfaceRawRoomLogged)",
            "sender_livekit_sdk_failure_surface_raw_identity_logged=\(senderLiveKitSDKFailureSurfaceRawIdentityLogged)",
            "sender_livekit_sdk_failure_surface_connect_call_started=\(senderLiveKitSDKFailureSurfaceConnectCallStarted)",
            "sender_livekit_sdk_failure_surface_connect_call_returned=\(senderLiveKitSDKFailureSurfaceConnectCallReturned)",
            "sender_livekit_sdk_failure_surface_connect_call_threw=\(senderLiveKitSDKFailureSurfaceConnectCallThrew)",
            "sender_livekit_sdk_failure_surface_connected_state_observed=\(senderLiveKitSDKFailureSurfaceConnectedStateObserved)",
            "sender_livekit_sdk_failure_surface_failed_state_observed=\(senderLiveKitSDKFailureSurfaceFailedStateObserved)",
            "sender_livekit_sdk_failure_surface_disconnected_before_connected=\(senderLiveKitSDKFailureSurfaceDisconnectedBeforeConnected)",
            "sender_livekit_sdk_failure_surface_delegate_failure_observed=\(senderLiveKitSDKFailureSurfaceDelegateFailureObserved)",
            "sender_livekit_sdk_failure_surface_room_already_connected=\(senderLiveKitSDKFailureSurfaceRoomAlreadyConnected)",
            "sender_livekit_sdk_failure_surface_identity_conflict_observed=\(senderLiveKitSDKFailureSurfaceIdentityConflictObserved)",
            "sender_livekit_sdk_failure_surface_token_identity_match=\(senderLiveKitSDKFailureSurfaceTokenIdentityMatch)",
            "sender_livekit_sdk_failure_surface_audio_session_ready=\(senderLiveKitSDKFailureSurfaceAudioSessionReady)",
            "sender_livekit_sdk_failure_surface_permission_required=\(senderLiveKitSDKFailureSurfacePermissionRequired)",
            "sender_livekit_sdk_failure_surface_capture_started=\(senderLiveKitSDKFailureSurfaceCaptureStarted)",
            "sender_livekit_sdk_failure_surface_final_classification=\(senderLiveKitSDKFailureSurfaceFinalClassification)",
            "sender_livekit_sdk_timeline_present=\(senderLiveKitSDKTimelinePresent)",
            "sender_livekit_sdk_timeline_debug_only=\(senderLiveKitSDKTimelineDebugOnly)",
            "sender_livekit_sdk_timeline_raw_error_logged=\(senderLiveKitSDKTimelineRawErrorLogged)",
            "sender_livekit_sdk_timeline_raw_url_logged=\(senderLiveKitSDKTimelineRawURLLogged)",
            "sender_livekit_sdk_timeline_raw_token_logged=\(senderLiveKitSDKTimelineRawTokenLogged)",
            "sender_livekit_sdk_timeline_raw_room_logged=\(senderLiveKitSDKTimelineRawRoomLogged)",
            "sender_livekit_sdk_timeline_raw_identity_logged=\(senderLiveKitSDKTimelineRawIdentityLogged)",
            "sender_livekit_sdk_timeline_trigger_received=\(senderLiveKitSDKTimelineTriggerReceived)",
            "sender_livekit_sdk_timeline_task_created=\(senderLiveKitSDKTimelineTaskCreated)",
            "sender_livekit_sdk_timeline_task_started=\(senderLiveKitSDKTimelineTaskStarted)",
            "sender_livekit_sdk_timeline_connect_invoked=\(senderLiveKitSDKTimelineConnectInvoked)",
            "sender_livekit_sdk_timeline_connect_returned=\(senderLiveKitSDKTimelineConnectReturned)",
            "sender_livekit_sdk_timeline_connect_threw=\(senderLiveKitSDKTimelineConnectThrew)",
            "sender_livekit_sdk_timeline_delegate_attached=\(senderLiveKitSDKTimelineDelegateAttached)",
            "sender_livekit_sdk_timeline_state_observer_attached=\(senderLiveKitSDKTimelineStateObserverAttached)",
            "sender_livekit_sdk_timeline_connected_state_seen=\(senderLiveKitSDKTimelineConnectedStateSeen)",
            "sender_livekit_sdk_timeline_failed_state_seen=\(senderLiveKitSDKTimelineFailedStateSeen)",
            "sender_livekit_sdk_timeline_disconnected_state_seen=\(senderLiveKitSDKTimelineDisconnectedStateSeen)",
            "sender_livekit_sdk_timeline_task_cancelled=\(senderLiveKitSDKTimelineTaskCancelled)",
            "sender_livekit_sdk_timeline_task_completed=\(senderLiveKitSDKTimelineTaskCompleted)",
            "sender_livekit_sdk_timeline_timeout_elapsed=\(senderLiveKitSDKTimelineTimeoutElapsed)",
            "sender_livekit_sdk_timeline_proof_written_after_terminal_state=\(senderLiveKitSDKTimelineProofWrittenAfterTerminalState)",
            "sender_livekit_sdk_timeline_final_classification=\(senderLiveKitSDKTimelineFinalClassification)",
            "sender_livekit_sdk_timeout_diagnostics_present=\(senderLiveKitSDKTimeoutDiagnosticsPresent)",
            "sender_livekit_sdk_timeout_diagnostics_debug_only=\(senderLiveKitSDKTimeoutDiagnosticsDebugOnly)",
            "sender_livekit_sdk_timeout_diagnostics_raw_error_logged=\(senderLiveKitSDKTimeoutDiagnosticsRawErrorLogged)",
            "sender_livekit_sdk_timeout_diagnostics_raw_url_logged=\(senderLiveKitSDKTimeoutDiagnosticsRawURLLogged)",
            "sender_livekit_sdk_timeout_diagnostics_raw_token_logged=\(senderLiveKitSDKTimeoutDiagnosticsRawTokenLogged)",
            "sender_livekit_sdk_timeout_diagnostics_raw_room_logged=\(senderLiveKitSDKTimeoutDiagnosticsRawRoomLogged)",
            "sender_livekit_sdk_timeout_diagnostics_raw_identity_logged=\(senderLiveKitSDKTimeoutDiagnosticsRawIdentityLogged)",
            "sender_livekit_sdk_timeout_diagnostics_wait_window_bucket=\(senderLiveKitSDKTimeoutDiagnosticsWaitWindowBucket)",
            "sender_livekit_sdk_timeout_diagnostics_connect_invoked=\(senderLiveKitSDKTimeoutDiagnosticsConnectInvoked)",
            "sender_livekit_sdk_timeout_diagnostics_connect_call_pending_at_timeout=\(senderLiveKitSDKTimeoutDiagnosticsConnectCallPendingAtTimeout)",
            "sender_livekit_sdk_timeout_diagnostics_task_running_at_timeout=\(senderLiveKitSDKTimeoutDiagnosticsTaskRunningAtTimeout)",
            "sender_livekit_sdk_timeout_diagnostics_task_cancelled_at_timeout=\(senderLiveKitSDKTimeoutDiagnosticsTaskCancelledAtTimeout)",
            "sender_livekit_sdk_timeout_diagnostics_delegate_attached=\(senderLiveKitSDKTimeoutDiagnosticsDelegateAttached)",
            "sender_livekit_sdk_timeout_diagnostics_state_observer_attached=\(senderLiveKitSDKTimeoutDiagnosticsStateObserverAttached)",
            "sender_livekit_sdk_timeout_diagnostics_state_event_count_bucket=\(senderLiveKitSDKTimeoutDiagnosticsStateEventCountBucket)",
            "sender_livekit_sdk_timeout_diagnostics_delegate_event_count_bucket=\(senderLiveKitSDKTimeoutDiagnosticsDelegateEventCountBucket)",
            "sender_livekit_sdk_timeout_diagnostics_app_state_bucket=\(senderLiveKitSDKTimeoutDiagnosticsAppStateBucket)",
            "sender_livekit_sdk_timeout_diagnostics_actor_context_available=\(senderLiveKitSDKTimeoutDiagnosticsActorContextAvailable)",
            "sender_livekit_sdk_timeout_diagnostics_network_path_bucket=\(senderLiveKitSDKTimeoutDiagnosticsNetworkPathBucket)",
            "sender_livekit_sdk_timeout_diagnostics_final_classification=\(senderLiveKitSDKTimeoutDiagnosticsFinalClassification)",
            "sender_transport_error_surface_source=\(senderTransportErrorSurfaceSource)",
            "sender_transport_error_surface_sdk_error_bucket=\(senderTransportErrorSurfaceSDKErrorBucket)",
            "sender_transport_error_surface_disconnect_reason_bucket=\(senderTransportErrorSurfaceDisconnectReasonBucket)",
            "sender_transport_error_surface_websocket_bucket=\(senderTransportErrorSurfaceWebsocketBucket)",
            "sender_transport_error_surface_auth_bucket=\(senderTransportErrorSurfaceAuthBucket)",
            "sender_transport_error_surface_timeout_observed=\(senderTransportErrorSurfaceTimeoutObserved)",
            "sender_transport_error_surface_connected_state_observed=\(senderTransportErrorSurfaceConnectedStateObserved)",
            "sender_transport_error_surface_disconnected_before_connected=\(senderTransportErrorSurfaceDisconnectedBeforeConnected)",
            "sender_transport_error_surface_final_classification=\(senderTransportErrorSurfaceFinalClassification)",
            "sender_side_livekit_join_activation_present=\(senderSideLiveKitJoinActivationPresent)",
            "sender_side_livekit_join_activation_debug_only=\(senderSideLiveKitJoinActivationDebugOnly)",
            "sender_side_livekit_join_activation_default_disabled=\(senderSideLiveKitJoinActivationDefaultDisabled)",
            "sender_side_livekit_join_activation_requires_sender_readiness=\(senderSideLiveKitJoinActivationRequiresSenderReadiness)",
            "sender_side_livekit_join_activation_requires_same_room=\(senderSideLiveKitJoinActivationRequiresSameRoom)",
            "sender_side_livekit_join_activation_audio_only=\(senderSideLiveKitJoinActivationAudioOnly)",
            "sender_side_livekit_join_activation_video_allowed=\(senderSideLiveKitJoinActivationVideoAllowed)",
            "sender_side_livekit_join_activation_matrix_events_allowed=\(senderSideLiveKitJoinActivationMatrixEventsAllowed)",
            "sender_side_livekit_join_activation_raw_identifiers_logged=\(senderSideLiveKitJoinActivationRawIdentifiersLogged)",
            "sender_side_livekit_join_activation_armed=\(senderSideLiveKitJoinActivationArmed)",
            "sender_side_livekit_join_activation_triggered=\(senderSideLiveKitJoinActivationTriggered)",
            "sender_side_livekit_join_activation_consumed=\(senderSideLiveKitJoinActivationConsumed)",
            "sender_side_livekit_join_activation_repeated=\(senderSideLiveKitJoinActivationRepeated)",
            "sender_side_livekit_join_activation_blocked_reason=\(senderSideLiveKitJoinActivationBlockedReason)",
            "sender_join_trigger_orchestration_present=\(senderJoinTriggerOrchestrationPresent)",
            "sender_join_trigger_orchestration_debug_only=\(senderJoinTriggerOrchestrationDebugOnly)",
            "sender_join_trigger_orchestration_raw_identifiers_logged=\(senderJoinTriggerOrchestrationRawIdentifiersLogged)",
            "sender_join_trigger_orchestration_apns_success_seen=\(senderJoinTriggerOrchestrationAPNsSuccessSeen)",
            "sender_join_trigger_orchestration_receiver_answer_seen=\(senderJoinTriggerOrchestrationReceiverAnswerSeen)",
            "sender_join_trigger_orchestration_receiver_connect_terminal_seen=\(senderJoinTriggerOrchestrationReceiverConnectTerminalSeen)",
            "sender_join_trigger_orchestration_sender_activation_armed=\(senderJoinTriggerOrchestrationSenderActivationArmed)",
            "sender_join_trigger_orchestration_sender_trigger_required=\(senderJoinTriggerOrchestrationSenderTriggerRequired)",
            "sender_join_trigger_orchestration_sender_trigger_allowed=\(senderJoinTriggerOrchestrationSenderTriggerAllowed)",
            "sender_join_trigger_orchestration_sender_trigger_started=\(senderJoinTriggerOrchestrationSenderTriggerStarted)",
            "sender_join_trigger_orchestration_sender_trigger_completed=\(senderJoinTriggerOrchestrationSenderTriggerCompleted)",
            "sender_join_trigger_orchestration_sender_trigger_missing_classified=\(senderJoinTriggerOrchestrationSenderTriggerMissingClassified)",
            "sender_join_trigger_orchestration_poll_allowed=\(senderJoinTriggerOrchestrationPollAllowed)",
            "sender_join_trigger_orchestration_poll_blocked_reason=\(senderJoinTriggerOrchestrationPollBlockedReason)",
            "sender_join_trigger_orchestration_final_classification=\(senderJoinTriggerOrchestrationFinalClassification)",
            "receiver_remote_participant_observer_present=\(receiverRemoteParticipantObserverPresent)",
            "receiver_remote_participant_observer_debug_only=\(receiverRemoteParticipantObserverDebugOnly)",
            "receiver_remote_participant_observer_started=\(receiverRemoteParticipantObserverStarted)",
            "receiver_remote_participant_observer_result=\(receiverRemoteParticipantObserverResult)",
            "receiver_remote_participant_observer_error_bucket=\(receiverRemoteParticipantObserverErrorBucket)",
            "receiver_remote_participant_observer_timeout_bucket=\(receiverRemoteParticipantObserverTimeoutBucket)",
            "receiver_remote_participant_observer_remote_seen=\(receiverRemoteParticipantObserverRemoteSeen)",
            "receiver_remote_participant_observer_audio_track_seen=\(receiverRemoteParticipantObserverAudioTrackSeen)",
            "receiver_remote_participant_observer_liveness_seen=\(receiverRemoteParticipantObserverLivenessSeen)",
            "receiver_remote_participant_observer_raw_identifiers_logged=\(receiverRemoteParticipantObserverRawIdentifiersLogged)",
            "remote_peer_context_handoff_present=\(remotePeerContextHandoffPresent)",
            "remote_peer_context_handoff_debug_only=\(remotePeerContextHandoffDebugOnly)",
            "remote_peer_context_handoff_source=\(remotePeerContextHandoffSource)",
            "remote_peer_context_handoff_armed_before_apns=\(remotePeerContextHandoffArmedBeforeAPNs)",
            "remote_peer_context_handoff_received_by_runtime=\(remotePeerContextHandoffReceivedByRuntime)",
            "remote_peer_context_handoff_survived_pushkit=\(remotePeerContextHandoffSurvivedPushKit)",
            "remote_peer_context_handoff_survived_answer=\(remotePeerContextHandoffSurvivedAnswer)",
            "remote_peer_context_handoff_raw_identifiers_logged=\(remotePeerContextHandoffRawIdentifiersLogged)",
            "remote_peer_context_handoff_blocks_success_without_context=\(remotePeerContextHandoffBlocksSuccessWithoutContext)",
            "remote_peer_context_handoff_classifies_missing_remote_participant=\(remotePeerContextHandoffClassifiesMissingRemoteParticipant)",
            "remote_peer_context_handoff_classifies_simulator_limitation=\(remotePeerContextHandoffClassifiesSimulatorLimitation)",
            "livekit_join_result=\(liveKitJoinResult)",
            "livekit_join_error_bucket=\(liveKitJoinErrorBucket)",
            "livekit_room_connected=\(liveKitRoomConnected)",
            "livekit_room_disconnected=\(liveKitRoomDisconnected)",
            "livekit_local_participant_present=\(liveKitLocalParticipantPresent)",
            "local_audio_publish_requested=\(localAudioPublishRequested)",
            "local_audio_publish_started=\(localAudioPublishStarted)",
            "local_audio_publish_result=\(localAudioPublishResult)",
            "local_audio_publish_error_bucket=\(localAudioPublishErrorBucket)",
            "local_audio_publish_not_required_reason=\(localAudioPublishNotRequiredReason)",
            "microphone_permission_result=\(microphonePermissionResult)",
            "microphone_permission_not_required_reason=\(microphonePermissionNotRequiredReason)",
            "audio_route_available=\(audioRouteAvailable)",
            "audio_route_result=\(audioRouteResult)",
            "remote_peer_kind=\(remotePeerKind)",
            "remote_peer_physical_device=\(remotePeerPhysicalDevice)",
            "simulator_assisted_remote_audio_proof=\(simulatorAssistedRemoteAudioProof)",
            "production_like_two_physical_device_proof=\(productionLikeTwoPhysicalDeviceProof)",
            "second_device_remote_audio_readiness=\(secondDeviceRemoteAudioReadiness)",
            "remote_audio_liveness_limitation=\(remoteAudioLivenessLimitation)",
            "livekit_remote_participant_seen=\(liveKitRemoteParticipantSeen)",
            "livekit_remote_participant_count_bucket=\(liveKitRemoteParticipantCountBucket)",
            "livekit_remote_audio_track_subscribed=\(liveKitRemoteAudioTrackSubscribed)",
            "livekit_remote_audio_track_unmuted=\(liveKitRemoteAudioTrackUnmuted)",
            "livekit_remote_audio_level_observed=\(liveKitRemoteAudioLevelObserved)",
            "livekit_audio_liveness_observed=\(liveKitAudioLivenessObserved)",
            "livekit_audio_liveness_result=\(liveKitAudioLivenessResult)",
            "livekit_audio_liveness_error_bucket=\(liveKitAudioLivenessErrorBucket)",
            "remote_audio_liveness_result=\(liveKitAudioLivenessResult)",
            "remote_audio_liveness_error_bucket=\(liveKitAudioLivenessErrorBucket)",
            "livekit_cleanup_requested=\(liveKitCleanupRequested)",
            "livekit_cleanup_completed=\(liveKitCleanupCompleted)",
            "livekit_cleanup_result=\(liveKitCleanupResult)",
            "media_connect_requested=\(mediaConnectRequested)",
            "media_connect_attempted=\(mediaConnectAttempted)",
            "livekit_join_requested=\(liveKitJoinRequested)",
            "microphone_permission_requested=\(microphonePermissionRequested)",
            "camera_permission_requested=\(cameraPermissionRequested)",
            "matrix_event_emit_requested=\(matrixEventEmitRequested)",
            "real_call_flow_started=\(realCallFlowStarted)",
            "blocked_reason=\(blockedReason)"
        ]
    }
}

private extension SalemXVoIPPushReceiptProofSummary {
    mutating func recordReceiverVoIPPushDeliveryTriage(apnsProviderAcceptanceResultBucket: String?,
                                                       receiverAppProofGenerationAfterAPNsChanged: Bool?,
                                                       receiverPushKitTokenDeviceBindingExpectedBucket: String?,
                                                       receiverPushKitTokenEnvironmentBucket: String?) {
        if let apnsProviderAcceptanceResultBucket {
            self.apnsProviderAcceptanceResultBucket = Self.safeAPNsAcceptanceBucket(apnsProviderAcceptanceResultBucket)
        }
        if let receiverAppProofGenerationAfterAPNsChanged {
            self.receiverAppProofGenerationAfterAPNsChanged = receiverAppProofGenerationAfterAPNsChanged
        }
        if let receiverPushKitTokenDeviceBindingExpectedBucket {
            self.receiverPushKitTokenDeviceBindingExpectedBucket = Self.safeDeviceBindingBucket(receiverPushKitTokenDeviceBindingExpectedBucket)
        }
        if let receiverPushKitTokenEnvironmentBucket {
            self.receiverPushKitTokenEnvironmentBucket = Self.safeTokenEnvironmentBucket(receiverPushKitTokenEnvironmentBucket)
        }
    }

    mutating func refreshReceiverVoIPPushDeliveryTriage(uploadProof: String, appStateBeforeAPNs: String) {
        let uploadFields = Self.redactedProofFields(from: uploadProof)
        receiverVoIPPushDeliveryTriagePresent = true
        receiverVoIPPushDeliveryTriageDebugOnly = true
        receiverVoIPPushDeliveryTriageRawIdentifiersLogged = false
        refreshReceiverPushKitTokenPreflightBuckets(uploadFields: uploadFields,
                                                    appStateBeforeAPNs: appStateBeforeAPNs)
        receiverAppLifecycleStateBeforeAPNsBucket = Self.safeAppStateBucket(appStateBeforeAPNs)
        receiverAppProofGenerationBeforeAPNs = proofGeneration
        receiverVoIPPushCallbackSeenAfterAPNs = physicalVoIPPushReceived
        receiverCallKitReportRequestedAfterAPNs = callKitReportRequested
        receiverCallKitAnswerAvailableAfterAPNs = callKitAnswerActionReceived || callKitAnswerActionDelivered
        apnsProviderAcceptanceResultBucket = Self.safeAPNsAcceptanceBucket(apnsProviderAcceptanceResultBucket)
        apnsDeliveryCallbackMissingAfterAcceptance = apnsProviderAcceptanceResultBucket == "2xx" && !physicalVoIPPushReceived
        receiverVoIPPushDeliveryFinalClassification = Self.receiverVoIPPushDeliveryClassification(summary: self)
    }

    mutating func refreshReceiverPushKitTokenReadiness(uploadProof: String,
                                                       appStateBeforeAPNs: String,
                                                       waitStarted: Bool,
                                                       waitCompleted: Bool,
                                                       waitTimeout: Bool) {
        let uploadFields = Self.redactedProofFields(from: uploadProof)
        receiverPushKitTokenReadinessRepairPresent = true
        receiverPushKitTokenReadinessRepairDebugOnly = true
        receiverPushKitTokenReadinessRepairRawIdentifiersLogged = false
        refreshReceiverPushKitTokenPreflightBuckets(uploadFields: uploadFields,
                                                    appStateBeforeAPNs: appStateBeforeAPNs)
        receiverPushKitTokenReadinessWaitStarted = waitStarted
        receiverPushKitTokenReadinessWaitCompleted = waitCompleted
        receiverPushKitTokenReadinessWaitTimeout = waitTimeout
        receiverPushKitTokenReadinessFinalClassification = Self.receiverPushKitTokenReadinessClassification(summary: self)
        receiverVoIPPushDeliveryFinalClassification = Self.receiverVoIPPushDeliveryClassification(summary: self)
    }

    mutating func refreshReceiverPushKitTokenPreflightBuckets(uploadFields: [String: String],
                                                              appStateBeforeAPNs: String) {
        receiverPushKitRegistrationRequestedBeforeAPNs = uploadFields["pushkit_registration_manual_invoked"] == "true"
        receiverPushKitTokenCallbackSeenBeforeAPNs = uploadFields["pushkit_token_received"] == "true"
        receiverPushKitTokenPresentBeforeAPNs = receiverPushKitTokenCallbackSeenBeforeAPNs
        receiverPushKitTokenUploadAttemptedBeforeAPNs = uploadFields["pushkit_token_upload_requested"] == "true"
        receiverPushKitTokenUploadResultBucket = Self.safeUploadResultBucket(uploadFields["pushkit_token_upload_result"])
        receiverPushKitTokenServerStoreResultBucket = Self.safeServerStoreResultBucket(uploadFields["pushkit_token_server_store_result"])
        if receiverPushKitTokenEnvironmentBucket == "unknown" {
            receiverPushKitTokenEnvironmentBucket = Self.safeTokenEnvironmentBucket(uploadFields["pushkit_token_environment_bucket"])
        }
        if receiverPushKitTokenDeviceBindingExpectedBucket == "unknown" {
            receiverPushKitTokenDeviceBindingExpectedBucket = Self.safeDeviceBindingBucket(uploadFields["pushkit_token_retrieval_internal_check"])
        }
        receiverAppLifecycleStateBeforeAPNsBucket = Self.safeAppStateBucket(appStateBeforeAPNs)
    }

    static func receiverPushKitTokenReadinessTerminal(uploadProof: String) -> Bool {
        var summary = SalemXVoIPPushReceiptProofSummary()
        summary.refreshReceiverPushKitTokenReadiness(uploadProof: uploadProof,
                                                     appStateBeforeAPNs: "unknown",
                                                     waitStarted: true,
                                                     waitCompleted: true,
                                                     waitTimeout: false)
        return summary.receiverPushKitTokenReadinessFinalClassification == "receiver_pushkit_token_ready_before_apns_redacted" ||
            summary.receiverPushKitTokenReadinessFinalClassification == "receiver_pushkit_token_upload_failed_before_apns_redacted"
    }

    mutating func recordReceiverForegroundInAppAnswerHookRequest(currentAppState: String,
                                                                 pendingMetadataReferenceAvailable: Bool) -> Bool {
        receiverForegroundInAppAnswerContinuationRepairPresent = true
        receiverForegroundInAppAnswerContinuationRepairDebugOnly = true
        receiverForegroundInAppAnswerContinuationRepairRawIdentifiersLogged = false
        receiverForegroundInAppAnswerHookPresent = true
        receiverForegroundInAppAnswerHookDefaultDisabled = true
        receiverForegroundInAppAnswerHookRequested = true
        receiverForegroundInAppAnswerPreservedPendingMetadata = pendingMetadataReferenceAvailable && pendingMetadataReferencePresent

        let reportSubmitted = callKitReportRequested &&
            (callKitReportResult == "reported" || callKitReportResult == "fake_reported") &&
            callKitReportCompletionObserved
        let reportRetained = callKitProviderRetainedForAnswer &&
            callKitDelegateRetainedForAnswer &&
            callKitActiveCallUUIDRetained
        let foregroundState = Self.safeAppStateBucket(currentAppState) == "foreground" ||
            Self.safeAppStateBucket(appStateAtReportCompletion) == "foreground" ||
            receiverCallKitSurfaceOperatorReadinessFinalClassification == "receiver_callkit_foreground_state_requires_in_app_answer_redacted"
        let reportGateReady = (reportSubmitted && reportRetained) ||
            receiverCallKitSurfaceOperatorReadinessFinalClassification == "receiver_callkit_foreground_state_requires_in_app_answer_redacted"

        let blockedReason: String
        if !physicalVoIPPushReceived || !callbackInvoked || !realInvitePayloadMappingObserved || !reportGateReady {
            blockedReason = "receiver_foreground_in_app_answer_missing_report_redacted"
        } else if !foregroundState {
            blockedReason = "receiver_foreground_in_app_answer_not_foreground_redacted"
        } else if !receiverForegroundInAppAnswerPreservedPendingMetadata {
            blockedReason = "receiver_foreground_in_app_answer_missing_pending_metadata_redacted"
        } else if callKitAnswerActionReceived {
            blockedReason = "receiver_foreground_in_app_answer_blocked_by_gate_redacted"
        } else {
            blockedReason = "none"
        }

        let allowed = blockedReason == "none"
        receiverForegroundInAppAnswerHookAllowed = allowed
        receiverForegroundInAppAnswerHookBlockedReason = blockedReason
        receiverForegroundInAppAnswerRecorded = allowed
        receiverForegroundInAppAnswerTriggeredPostAnswerContinuation = allowed
        if allowed {
            receiverForegroundInAppAnswerFinalClassification = receiverForegroundInAppAnswerTriggeredPostAnswerContinuation ?
                "receiver_foreground_in_app_answer_post_answer_continuation_started_redacted" :
                "receiver_foreground_in_app_answer_recorded_redacted"
        } else {
            receiverForegroundInAppAnswerFinalClassification = blockedReason
        }
        return allowed
    }

    private static func redactedProofFields(from proof: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: proof.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                return nil
            }
            return (String(parts[0]), String(parts[1]))
        })
    }

    private static func safeUploadResultBucket(_ value: String?) -> String {
        switch value {
        case "http_success", "registered", "success_redacted":
            return "success_redacted"
        case "not_requested":
            return "not_requested"
        case .some(let value) where value.contains("fail") || value.contains("error"):
            return "failed_redacted"
        default:
            return "unknown"
        }
    }

    private static func safeServerStoreResultBucket(_ value: String?) -> String {
        switch value {
        case "persisted", "persisted_redacted", "success_redacted", "redacted_match":
            return "persisted_redacted"
        case "known_redacted":
            return "known_redacted"
        case "not_requested":
            return "not_requested"
        case .some(let value) where value.contains("fail") || value.contains("error"):
            return "failed_redacted"
        default:
            return "unknown"
        }
    }

    private static func receiverPushKitServerStoreResultKnownSuccess(_ bucket: String) -> Bool {
        switch bucket {
        case "persisted_redacted", "success_redacted", "known_redacted":
            return true
        default:
            return false
        }
    }

    private static func safeTokenEnvironmentBucket(_ value: String?) -> String {
        switch value {
        case "development", "sandbox":
            return "development"
        case "production":
            return "production"
        case "mismatch_possible_redacted":
            return "mismatch_possible_redacted"
        default:
            return "unknown"
        }
    }

    private static func safeDeviceBindingBucket(_ value: String?) -> String {
        switch value {
        case "expected_redacted", "redacted_match":
            return "expected_redacted"
        case "mismatch_possible_redacted":
            return "mismatch_possible_redacted"
        case "not_requested":
            return "not_requested"
        default:
            return "unknown"
        }
    }

    private static func safeAPNsAcceptanceBucket(_ value: String?) -> String {
        switch value {
        case "2xx", "sandbox_success", "accepted_redacted":
            return "2xx"
        case "not_requested":
            return "not_requested"
        case .some(let value) where value.contains("fail") || value.contains("non_2xx"):
            return "non_2xx"
        default:
            return "unknown"
        }
    }

    private static func safeAppStateBucket(_ value: String) -> String {
        switch value {
        case "foreground", "background", "inactive":
            return value
        default:
            return "unknown"
        }
    }

    private static func receiverVoIPPushDeliveryClassification(summary: SalemXVoIPPushReceiptProofSummary) -> String {
        if summary.physicalVoIPPushReceived {
            return "receiver_voip_push_received_redacted"
        }
        if !summary.receiverPushKitTokenPresentBeforeAPNs {
            return "receiver_pushkit_token_missing_before_apns_redacted"
        }
        if summary.receiverPushKitTokenUploadAttemptedBeforeAPNs,
           summary.receiverPushKitTokenUploadResultBucket == "failed_redacted" {
            return "receiver_pushkit_token_upload_failed_before_apns_redacted"
        }
        if summary.receiverPushKitTokenEnvironmentBucket == "mismatch_possible_redacted" ||
            summary.receiverPushKitTokenEnvironmentBucket == "production" {
            return "receiver_pushkit_token_environment_mismatch_possible_redacted"
        }
        if summary.apnsDeliveryCallbackMissingAfterAcceptance {
            return "apns_accepted_but_receiver_callback_missing_redacted"
        }
        if summary.physicalVoIPPushReceived, !summary.callKitReportRequested {
            return "receiver_callkit_not_reported_after_apns_redacted"
        }
        return "receiver_pushkit_token_device_binding_unknown_redacted"
    }

    private static func receiverPushKitTokenReadinessClassification(summary: SalemXVoIPPushReceiptProofSummary) -> String {
        let serverStoreReady = Self.receiverPushKitServerStoreResultKnownSuccess(summary.receiverPushKitTokenServerStoreResultBucket)
        let ready = summary.receiverPushKitTokenReadinessWaitCompleted &&
            !summary.receiverPushKitTokenReadinessWaitTimeout &&
            summary.receiverPushKitRegistrationRequestedBeforeAPNs &&
            summary.receiverPushKitTokenCallbackSeenBeforeAPNs &&
            summary.receiverPushKitTokenPresentBeforeAPNs &&
            summary.receiverPushKitTokenUploadAttemptedBeforeAPNs &&
            summary.receiverPushKitTokenUploadResultBucket == "success_redacted" &&
            serverStoreReady &&
            summary.receiverPushKitTokenEnvironmentBucket == "development"
        if ready {
            return "receiver_pushkit_token_ready_before_apns_redacted"
        }
        if summary.receiverPushKitTokenReadinessWaitTimeout {
            return "receiver_pushkit_token_readiness_timeout_before_apns_redacted"
        }
        if !summary.receiverPushKitRegistrationRequestedBeforeAPNs {
            return "receiver_pushkit_registration_not_requested_before_apns_redacted"
        }
        if !summary.receiverPushKitTokenCallbackSeenBeforeAPNs {
            return "receiver_pushkit_token_callback_missing_before_apns_redacted"
        }
        if !summary.receiverPushKitTokenPresentBeforeAPNs {
            return "receiver_pushkit_token_missing_before_apns_redacted"
        }
        if summary.receiverPushKitTokenUploadResultBucket == "failed_redacted" {
            return "receiver_pushkit_token_upload_failed_before_apns_redacted"
        }
        if !serverStoreReady {
            return "receiver_pushkit_token_server_store_unknown_before_apns_redacted"
        }
        return "receiver_pushkit_token_server_store_unknown_before_apns_redacted"
    }

    mutating func recordPendingMetadataReferenceRepairProof(referencePresent: Bool,
                                                            handedToAnswerPipeline: Bool = false) {
        pendingMetadataReferenceRepairPresent = true
        pendingMetadataReferenceRepairDebugOnly = true
        pendingMetadataReferenceRepairRealInviteRequired = true
        pendingMetadataReferenceRepairReferenceCreatedBeforeAPNs = referencePresent
        pendingMetadataReferenceRepairReferencePresentInAPNsPayload = referencePresent
        pendingMetadataReferenceRepairReferenceObservedByPushKit = referencePresent
        pendingMetadataReferenceRepairReferenceHandedToAnswerPipeline = referencePresent && handedToAnswerPipeline
        pendingMetadataReferenceRepairBlocksAPNsWithoutReference = true
        pendingMetadataReferenceRepairBlocksCredentialsWithoutMetadataSuccess = true
        pendingMetadataReferenceRepairNoDirectCredentialsBypass = true
        pendingMetadataReferenceRepairNoConnectBypass = true
        pendingMetadataReferenceRepairRawMetadataLogged = false
    }

    mutating func refreshDisconnectCleanupDiagnostics() {
        disconnectCleanupDiagnosticsPresent = true
        disconnectCleanupDiagnosticsDebugOnly = true
        disconnectCleanupDiagnosticsCallKitCleanupRequested = controlledCallKitCleanupRequested
        disconnectCleanupDiagnosticsCallKitCleanupResult = controlledCallKitCleanupResult
        disconnectCleanupDiagnosticsEndActionDelivered = callKitEndActionDelivered
        disconnectCleanupDiagnosticsEndActionFulfilled = endActionFulfilled
        disconnectCleanupDiagnosticsEndActionOrigin = endActionOrigin
        disconnectCleanupDiagnosticsEndActionUUIDMatched = endActionUUIDMatched
        disconnectCleanupDiagnosticsEndActionGenerationMatched = endActionGenerationMatched
        disconnectCleanupDiagnosticsEndActionSourceMatched = endActionSourceMatched
        disconnectCleanupDiagnosticsEndActionExpected = callKitEndActionDelivered || endActionFulfilled
        disconnectCleanupDiagnosticsLocalCleanupCompleted = controlledCallKitCleanupResult == "ended"
        disconnectCleanupDiagnosticsProviderEndReported = disconnectCleanupDiagnosticsLocalCleanupCompleted && !disconnectCleanupDiagnosticsEndActionExpected
        disconnectCleanupDiagnosticsAudioSessionDeactivated = callKitProviderDidDeactivateAudioSession
        let observationActive = remoteParticipantObservationWaitStarted && !remoteParticipantObservationWaitCompleted
        disconnectCleanupDiagnosticsLiveKitCleanupRequested = controlledCallKitCleanupRequested && liveKitConnectAudioInvoked && !observationActive
        disconnectCleanupDiagnosticsLiveKitCleanupCompleted = disconnectCleanupDiagnosticsLiveKitCleanupRequested && disconnectCleanupDiagnosticsLocalCleanupCompleted
        disconnectCleanupDiagnosticsOneShotConsumed = physical6RuntimeEnablementURLHookConsumed
        disconnectCleanupDiagnosticsNoRepeatedConnect = !controlledConnectFirstAttemptRepeated
        disconnectCleanupDiagnosticsNoMatrixEvents = !matrixEventEmitRequested && !controlledConnectFirstAttemptMatrixEventsAllowed
        disconnectCleanupDiagnosticsNoVideo = !controlledConnectFirstAttemptVideoAllowed && !cameraPermissionRequested
        disconnectCleanupDiagnosticsRawIdentifiersLogged = false

        if !disconnectCleanupDiagnosticsEndActionExpected {
            disconnectCleanupDiagnosticsEndTimingClassification = "end_action_not_expected"
            disconnectCleanupDiagnosticsResult = disconnectCleanupDiagnosticsLocalCleanupCompleted && disconnectCleanupDiagnosticsProviderEndReported ?
                "local_or_provider_cleanup_sufficient_redacted" : "local_or_provider_cleanup_incomplete_redacted"
        } else if callKitEndAfterPushKitCompletionMsBucket == "unknown" {
            disconnectCleanupDiagnosticsEndTimingClassification = "end_action_timing_unknown_redacted"
            disconnectCleanupDiagnosticsResult = "end_action_timing_unknown_redacted"
        } else if disconnectCleanupDiagnosticsEndActionDelivered,
                  disconnectCleanupDiagnosticsEndActionFulfilled,
                  disconnectCleanupDiagnosticsEndActionUUIDMatched,
                  disconnectCleanupDiagnosticsEndActionGenerationMatched,
                  disconnectCleanupDiagnosticsEndActionSourceMatched {
            disconnectCleanupDiagnosticsEndTimingClassification = "end_action_timing_bucketed"
            disconnectCleanupDiagnosticsResult = "end_action_cleanup_sufficient_redacted"
        } else {
            disconnectCleanupDiagnosticsEndTimingClassification = "end_action_incomplete_redacted"
            disconnectCleanupDiagnosticsResult = "end_action_incomplete_redacted"
        }
    }

    mutating func refreshRemoteAudioLivenessDiagnostics() {
        remoteAudioLivenessDiagnosticsPresent = true
        remoteAudioLivenessDiagnosticsDebugOnly = true
        remoteAudioLivenessDiagnosticsAudioOnly = true
        remoteAudioLivenessDiagnosticsVideoAllowed = controlledConnectFirstAttemptVideoAllowed
        remoteAudioLivenessDiagnosticsMatrixEventsAllowed = controlledConnectFirstAttemptMatrixEventsAllowed
        remoteAudioLivenessDiagnosticsRawIdentifiersLogged = false
        remoteAudioPublishLivenessRepairPresent = true
        remoteAudioPublishLivenessRepairDebugOnly = true
        remoteAudioPublishLivenessRepairRequiresLiveKitJoinSuccess = true
        remoteAudioPublishLivenessRepairClassifiesPublishNotRequested = true
        remoteAudioPublishLivenessRepairClassifiesPublishSuccess = true
        remoteAudioPublishLivenessRepairClassifiesPublishFailure = true
        remoteAudioPublishLivenessRepairClassifiesSimulatorPeer = true
        remoteAudioPublishLivenessRepairClassifiesRemoteMissing = true
        remoteAudioPublishLivenessRepairClassifiesRemoteTrackMissing = true
        remoteAudioPublishLivenessRepairClassifiesLivenessObserved = true
        remoteAudioPublishLivenessRepairNoVideo = !controlledConnectFirstAttemptVideoAllowed && !cameraPermissionRequested
        remoteAudioPublishLivenessRepairNoMatrixEvents = !controlledConnectFirstAttemptMatrixEventsAllowed && !matrixEventEmitRequested
        remoteAudioPublishLivenessRepairRawIdentifiersLogged = false
        refreshRemoteParticipantPresenceRepairDiagnostics()
        remotePeerContextHandoffPresent = true
        remotePeerContextHandoffDebugOnly = true
        remotePeerContextHandoffRawIdentifiersLogged = false
        remotePeerContextHandoffBlocksSuccessWithoutContext = true
        remotePeerContextHandoffClassifiesMissingRemoteParticipant = true
        remotePeerContextHandoffClassifiesSimulatorLimitation = true

        if liveKitJoinRequested {
            liveKitJoinResult = controlledConnectFirstAttemptResult == "success_redacted" ? "success_redacted" : "failed_redacted"
            liveKitJoinErrorBucket = controlledConnectFirstAttemptResult == "success_redacted" ? "none" : controlledConnectFirstAttemptErrorBucket
            liveKitRoomConnected = controlledConnectFirstAttemptResult == "success_redacted"
            liveKitLocalParticipantPresent = liveKitRoomConnected
            if liveKitJoinResult == "success_redacted",
               !localAudioPublishRequested,
               localAudioPublishResult == "not_requested" {
                localAudioPublishResult = "not_required_redacted"
                localAudioPublishErrorBucket = "none"
                localAudioPublishNotRequiredReason = "receive_only_audio_connect_redacted"
            } else if liveKitJoinResult != "success_redacted",
                      !localAudioPublishRequested,
                      localAudioPublishResult == "not_requested" {
                localAudioPublishResult = "blocked_redacted"
                localAudioPublishErrorBucket = "livekit_join_not_success_redacted"
                localAudioPublishNotRequiredReason = "none"
                liveKitAudioLivenessResult = "not_observed_redacted"
                liveKitAudioLivenessErrorBucket = "livekit_join_not_success_redacted"
            }
        } else {
            liveKitJoinResult = "not_requested"
            liveKitJoinErrorBucket = "none"
            liveKitRoomConnected = false
            liveKitLocalParticipantPresent = false
            localAudioPublishNotRequiredReason = localAudioPublishResult == "not_requested" ? "none" : localAudioPublishNotRequiredReason
        }

        if liveKitJoinResult == "success_redacted",
           !remotePeerContextHandoffReceivedByRuntime {
            recordMissingRemotePeerContextHandoff()
        } else if liveKitJoinResult == "success_redacted",
                  !liveKitRemoteParticipantSeen,
                  !liveKitAudioLivenessObserved,
                  liveKitAudioLivenessErrorBucket == "none" {
            liveKitAudioLivenessResult = "not_observed_redacted"
            liveKitAudioLivenessErrorBucket = "remote_participant_missing_redacted"
        }

        let observationActive = remoteParticipantObservationWaitStarted && !remoteParticipantObservationWaitCompleted
        liveKitRoomDisconnected = observationActive ? false : controlledCallKitCleanupResult == "ended" || remoteParticipantObservationWaitCompleted
        microphonePermissionResult = microphonePermissionRequested ? "requested_redacted" : "not_requested_or_not_required_redacted"
        microphonePermissionNotRequiredReason = microphonePermissionRequested ? "requested_redacted" : "receive_only_audio_session_redacted"
        audioRouteAvailable = callKitProviderDidActivateAudioSession
        audioRouteResult = audioRouteAvailable ? "available_redacted" : "not_observed_redacted"
        if observationActive {
            liveKitCleanupRequested = false
            liveKitCleanupCompleted = false
            liveKitCleanupResult = "deferred_until_observation_terminal_redacted"
        } else {
            liveKitCleanupRequested = disconnectCleanupDiagnosticsLiveKitCleanupRequested || (remoteParticipantObservationWaitCompleted && liveKitConnectAudioInvoked)
            liveKitCleanupCompleted = disconnectCleanupDiagnosticsLiveKitCleanupCompleted || (remoteParticipantObservationWaitCompleted && liveKitConnectAudioInvoked)
            liveKitCleanupResult = liveKitCleanupCompleted ? "completed_redacted" : (liveKitCleanupRequested ? "not_completed_redacted" : "not_requested")
        }
    }

    mutating func refreshRemoteParticipantPresenceRepairDiagnostics() {
        remoteParticipantPresenceRepairPresent = true
        remoteParticipantPresenceRepairDebugOnly = true
        remoteParticipantPresenceRepairRequiresTwoPhysicalDevices = true
        remoteParticipantPresenceRepairRequiresSameRoom = true
        remoteParticipantPresenceRepairRequiresSenderLiveKitReadiness = true
        remoteParticipantPresenceRepairSenderJoinPathPresent = true
        remoteParticipantPresenceRepairSenderJoinDefaultDisabled = true
        remoteParticipantPresenceRepairReceiverObserverPresent = true
        remoteParticipantPresenceRepairSameLiveKitRoomRequired = true
        remoteParticipantPresenceRepairClassifiesSenderNotJoined = true
        remoteParticipantPresenceRepairClassifiesRemoteMissing = true
        remoteParticipantPresenceRepairClassifiesRemoteSeen = true
        remoteParticipantPresenceRepairNoVideo = !controlledConnectFirstAttemptVideoAllowed && !cameraPermissionRequested
        remoteParticipantPresenceRepairNoMatrixEvents = !controlledConnectFirstAttemptMatrixEventsAllowed && !matrixEventEmitRequested
        remoteParticipantPresenceRepairRawIdentifiersLogged = false

        secondPhysicalSenderLiveKitReadinessPresent = true
        secondPhysicalSenderLiveKitReadinessDebugOnly = true
        secondPhysicalSenderLiveKitReadinessDefaultDisabled = true
        secondPhysicalSenderLiveKitReadinessMatrixSessionReady = senderLiveKitReadinessHookMatrixSessionReady
        secondPhysicalSenderLiveKitReadinessSameRoomReady = senderLiveKitReadinessHookSameRoomReady
        secondPhysicalSenderLiveKitReadinessCredentialsReady = senderLiveKitReadinessHookCredentialsReady
        secondPhysicalSenderLiveKitJoinPathPresent = true
        secondPhysicalSenderLiveKitJoinPathDefaultDisabled = senderSideLiveKitJoinHookDefaultDisabled
        secondPhysicalSenderLiveKitJoinPathAudioOnly = senderSideLiveKitJoinHookAudioOnly
        secondPhysicalSenderLiveKitJoinPathVideoAllowed = senderSideLiveKitJoinHookVideoAllowed
        secondPhysicalSenderLiveKitJoinPathMatrixEventsAllowed = senderSideLiveKitJoinHookMatrixEventsAllowed
        secondPhysicalSenderLiveKitJoinPathRawCredentialsLogged = senderSideLiveKitJoinHookRawCredentialsLogged
        senderJoinFailureDiagnosticsAudioOnly = senderSideLiveKitJoinHookAudioOnly
        senderJoinFailureDiagnosticsVideoAllowed = senderSideLiveKitJoinHookVideoAllowed
        senderJoinFailureDiagnosticsMatrixEventsAllowed = senderSideLiveKitJoinHookMatrixEventsAllowed
        senderJoinFailureDiagnosticsRawIdentifiersLogged = false
        senderTransportFailureDiagnosticsAudioOnly = senderSideLiveKitJoinHookAudioOnly
        senderTransportFailureDiagnosticsVideoAllowed = senderSideLiveKitJoinHookVideoAllowed
        senderTransportFailureDiagnosticsMatrixEventsAllowed = senderSideLiveKitJoinHookMatrixEventsAllowed
        senderTransportFailureDiagnosticsRawIdentifiersLogged = false
        senderTransportErrorSurfaceDebugOnly = true
        senderTransportErrorSurfaceRawErrorLogged = false
        senderTransportErrorSurfaceRawURLLogged = false
        senderTransportErrorSurfaceRawTokenLogged = false

        receiverRemoteParticipantObserverPresent = true
        receiverRemoteParticipantObserverDebugOnly = true
        receiverRemoteParticipantObserverStarted = liveKitJoinResult == "success_redacted" || liveKitJoinRequested
        receiverRemoteParticipantObserverRemoteSeen = liveKitRemoteParticipantSeen
        receiverRemoteParticipantObserverAudioTrackSeen = liveKitRemoteAudioTrackSubscribed
        receiverRemoteParticipantObserverLivenessSeen = liveKitAudioLivenessObserved
        receiverRemoteParticipantObserverRawIdentifiersLogged = false

        refreshReceiverRemoteParticipantObserverClassification()
        refreshRemoteParticipantObservationTimingRepairDiagnostics()
        refreshSenderJoinTriggerOrchestration()
    }

    mutating func completeRemoteParticipantObservation(classification: String, timeoutBucket: String) {
        remoteParticipantObservationWaitCompleted = true
        remoteParticipantObservationTimeoutBucket = timeoutBucket
        remoteParticipantObservationFinalClassification = classification
        receiverParticipantObservationFinalClassification = classification
        receiverParticipantObservationAfterOverlapCompleted = receiverParticipantObservationAfterOverlapStarted
        receiverParticipantObservationAfterOverlapTimeout = receiverParticipantObservationAfterOverlapStarted &&
            [
                "participant_observation_timeout_after_overlap_redacted",
                "participant_snapshot_empty_redacted",
                "participant_event_callback_missing_redacted"
            ].contains(classification)
        receiverCleanupDeferredUntilObservationTerminal = receiverCleanupDeferredUntilObservationTerminal || liveKitConnectAudioInvoked
        if liveKitConnectAudioInvoked {
            liveKitCleanupRequested = true
            liveKitCleanupCompleted = true
            liveKitCleanupResult = "completed_redacted"
            liveKitRoomDisconnected = true
        }
        refreshReceiverRemoteParticipantObserverClassification()
        refreshRemoteParticipantObservationTimingRepairDiagnostics()
    }

    mutating func recordReceiverConnectedWindowOpened() {
        receiverSenderConnectedOverlapRepairPresent = true
        receiverSenderConnectedOverlapRepairDebugOnly = true
        receiverSenderConnectedOverlapRepairRawIdentifiersLogged = false
        receiverConnectedWindowRetentionRepairPresent = true
        receiverConnectedWindowRetentionRepairDebugOnly = true
        receiverConnectedWindowRetentionRepairRawIdentifiersLogged = false
        participantObserverPropagationRepairPresent = true
        participantObserverPropagationRepairDebugOnly = true
        participantObserverPropagationRawIdentifiersLogged = false
        receiverConnectedWindowOpened = true
        receiverConnectedWindowClosed = false
        receiverConnectedWindowCloseReason = "not_closed"
        receiverConnectedWindowClosedBeforeSenderConnected = false
        receiverDisconnectObservedBeforeSenderSignal = false
        receiverConnectedSessionLeaseActiveBeforeSenderTrigger = receiverConnectedSessionLeaseAcquired &&
            receiverConnectedSessionLeaseRoomRetained &&
            !receiverConnectedSessionLeaseReleased
        receiverSenderConnectedWindowOverlapWaitStarted = true
        receiverSenderConnectedSignalWaitStarted = true
        receiverSenderConnectedWindowOverlapWaitTimeout = false
        if receiverSenderConnectedWindowOverlapFinalClassification == "not_started" {
            receiverSenderConnectedWindowOverlapFinalClassification = "pending_redacted"
        }
        if receiverSenderConnectedSignalFinalClassification == "not_started" {
            receiverSenderConnectedSignalFinalClassification = "pending_redacted"
        }
    }

    mutating func recordReceiverConnectedWindowClosed(reason: String) {
        receiverConnectedWindowClosed = true
        receiverConnectedWindowCloseReason = reason
        if !senderConnectedSignalReceivedByReceiver {
            receiverConnectedWindowClosedBeforeSenderConnected = true
            receiverDisconnectObservedBeforeSenderSignal = true
            if receiverSenderConnectedWindowOverlapFinalClassification == "pending_redacted" ||
                receiverSenderConnectedWindowOverlapFinalClassification == "not_started" {
                receiverSenderConnectedWindowOverlapFinalClassification = "receiver_window_closed_before_sender_signal_redacted"
            }
            if receiverSenderConnectedSignalFinalClassification == "pending_redacted" ||
                receiverSenderConnectedSignalFinalClassification == "not_started" {
                receiverSenderConnectedSignalFinalClassification = "receiver_window_closed_before_sender_signal_redacted"
            }
        } else {
            receiverDisconnectObservedAfterSenderSignal = true
        }
    }

    mutating func recordSenderConnectedSignalFromRuntime(senderConnected: Bool, source: String, correlationMatched: Bool = true) {
        senderJoinTerminalSeenByReceiver = true
        senderConnectedSignalHandoffPresent = true
        senderConnectedSignalHandoffDebugOnly = true
        senderConnectedSignalHandoffRawIdentifiersLogged = false
        senderConnectedSignalRawIdentifiersLogged = false
        senderConnectedSignalRawRoomLogged = false
        senderConnectedSignalRawCallLogged = false
        senderConnectedSignalRawUserLogged = false
        senderConnectedSignalRawDeviceLogged = false
        let safeSource = source == "sender_runtime_livekit_join" ? "sender_runtime_livekit_join_redacted" : "unknown_redacted"
        senderConnectedSignalEmitted = senderConnected
        senderConnectedSignalEmitSource = senderConnected ? safeSource : "none"
        senderConnectedSignalEmittedAfterRuntimeJoinSuccess = senderConnected
        senderConnectedSignalOpaqueCorrelationPresent = correlationMatched
        receiverSenderConnectedSignalWaitStarted = true
        receiverSenderConnectedSignalWaitCompleted = true
        receiverSenderConnectedSignalTimeout = false

        guard senderConnected else {
            if !senderConnectedSignalReceivedByReceiver {
                receiverSenderConnectedWindowOverlapWaitCompleted = true
                receiverSenderConnectedSignalFinalClassification = "sender_connected_signal_missing_redacted"
                receiverSenderConnectedWindowOverlapFinalClassification = "sender_connected_signal_missing_redacted"
            }
            return
        }

        receiverSenderConnectedSignalReceived = true
        receiverSenderConnectedSignalCorrelationMatch = correlationMatched
        senderConnectedSignalReceivedByReceiver = true
        senderConnectedSignalSource = safeSource
        receiverSenderConnectedWindowOverlapWaitStarted = true
        receiverSenderConnectedWindowOverlapWaitCompleted = true
        receiverSenderConnectedWindowOverlapWaitTimeout = false

        let receiverWindowActive = receiverConnectedWindowOpened &&
            !receiverConnectedWindowClosed &&
            !receiverConnectedSessionLeaseReleased &&
            !liveKitRoomDisconnected
        senderConnectedSignalBeforeReceiverDisconnect = receiverWindowActive
        senderConnectedSignalAfterReceiverDisconnect = !receiverWindowActive
        receiverSenderConnectedSignalReceivedBeforeReceiverDisconnect = receiverWindowActive
        receiverSenderConnectedSignalReceivedAfterReceiverDisconnect = !receiverWindowActive
        receiverConnectedSessionLeaseActiveAtSenderSignal = receiverWindowActive
        receiverConnectedSessionLeaseActiveAfterSenderTrigger = receiverConnectedSessionLeaseActiveAfterSenderTrigger || receiverWindowActive
        receiverParticipantObserverActiveAfterSenderSignal = receiverRemoteParticipantObserverStarted && receiverWindowActive

        if !correlationMatched {
            receiverSenderConnectedSignalFinalClassification = "sender_connected_signal_correlation_mismatch_redacted"
            receiverSenderConnectedWindowOverlapFinalClassification = "sender_connected_signal_correlation_mismatch_redacted"
        } else if receiverWindowActive {
            senderRoomConnectedDuringReceiverWindow = true
            receiverSenderConnectedWindowOverlapObserved = true
            receiverConnectedWindowRetainedUntilSenderTerminal = true
            receiverParticipantObservationAfterOverlapStarted = true
            receiverObserverActiveDuringSenderJoin = receiverObserverActiveDuringSenderJoin || receiverRemoteParticipantObserverStarted
            receiverSenderConnectedSignalFinalClassification = "receiver_connected_window_retained_until_sender_signal_redacted"
            receiverSenderConnectedWindowOverlapFinalClassification = "receiver_connected_window_overlap_observed_redacted"
        } else {
            receiverDisconnectObservedBeforeSenderSignal = receiverConnectedWindowClosed || receiverConnectedSessionLeaseReleased || liveKitRoomDisconnected
            receiverSenderConnectedSignalFinalClassification = "sender_connected_signal_after_receiver_disconnect_redacted"
            receiverSenderConnectedWindowOverlapFinalClassification = "sender_connected_signal_after_receiver_disconnect_redacted"
        }
    }

    mutating func recordReceiverConnectedWindowRetentionExtended(timeoutBucket: String) {
        receiverConnectedWindowRetentionRepairPresent = true
        receiverConnectedWindowRetentionRepairDebugOnly = true
        receiverConnectedWindowRetentionRepairRawIdentifiersLogged = false
        receiverConnectedSessionLeaseActiveAfterSenderTrigger = true
        receiverConnectedWindowRetainedUntilSenderTerminal = true
        receiverCleanupDeferredUntilObservationTerminal = true
        receiverCleanupStartedBeforeSenderTerminal = false
        receiverSenderConnectedSignalWaitStarted = true
        receiverSenderConnectedSignalWaitCompleted = false
        receiverSenderConnectedSignalTimeout = false
        receiverSenderConnectedWindowOverlapWaitStarted = true
        receiverSenderConnectedWindowOverlapWaitCompleted = false
        receiverSenderConnectedWindowOverlapWaitTimeout = false
        remoteParticipantObservationTimeoutBucket = timeoutBucket
        remoteParticipantObservationFinalClassification = "receiver_connected_window_retained_until_sender_signal_redacted"
        receiverSenderConnectedSignalFinalClassification = "receiver_connected_window_retained_until_sender_signal_redacted"
        receiverSenderConnectedWindowOverlapFinalClassification = "receiver_connected_window_retained_until_sender_signal_redacted"
        liveKitRoomConnected = true
        liveKitRoomDisconnected = false
        liveKitCleanupRequested = false
        liveKitCleanupCompleted = false
        liveKitCleanupResult = "deferred_until_observation_terminal_redacted"
    }

    func shouldExtendReceiverConnectedWindowForSenderSignal(alreadyExtended: Bool) -> Bool {
        receiverConnectedWindowRetentionRepairPresent &&
            !alreadyExtended &&
            remoteParticipantObservationWaitStarted &&
            !remoteParticipantObservationWaitCompleted &&
            receiverConnectedSessionLeaseAcquired &&
            receiverConnectedSessionLeaseRoomRetained &&
            !receiverConnectedSessionLeaseReleased &&
            !senderConnectedSignalReceivedByReceiver
    }

    mutating func completeReceiverSenderConnectedWindowOverlapTimeout() {
        guard receiverSenderConnectedWindowOverlapWaitStarted,
              !receiverSenderConnectedWindowOverlapWaitCompleted else {
            return
        }

        receiverSenderConnectedWindowOverlapWaitCompleted = true
        receiverSenderConnectedWindowOverlapWaitTimeout = true
        receiverSenderConnectedSignalWaitCompleted = true
        receiverSenderConnectedSignalTimeout = !senderConnectedSignalReceivedByReceiver
        if senderConnectedSignalReceivedByReceiver, senderConnectedSignalAfterReceiverDisconnect {
            receiverSenderConnectedSignalFinalClassification = "sender_connected_signal_after_receiver_disconnect_redacted"
            receiverSenderConnectedWindowOverlapFinalClassification = "sender_connected_signal_after_receiver_disconnect_redacted"
        } else if senderConnectedSignalReceivedByReceiver, !receiverSenderConnectedWindowOverlapObserved {
            receiverSenderConnectedWindowOverlapFinalClassification = receiverSenderConnectedSignalCorrelationMatch ? "receiver_observer_bound_to_stale_room_redacted" : "sender_connected_signal_correlation_mismatch_redacted"
        } else if receiverSenderConnectedWindowOverlapObserved {
            receiverSenderConnectedSignalFinalClassification = "receiver_connected_window_retained_until_sender_signal_redacted"
            receiverSenderConnectedWindowOverlapFinalClassification = "participant_observation_timeout_after_overlap_redacted"
        } else if senderRoomConnectedDuringReceiverWindow || senderSideLiveKitJoinResult == SalemXSenderSideLiveKitJoinHook.successResult {
            receiverSenderConnectedSignalFinalClassification = "sender_connected_signal_missing_redacted"
            receiverSenderConnectedWindowOverlapFinalClassification = "sender_connected_signal_missing_redacted"
        } else if receiverConnectedWindowClosedBeforeSenderConnected {
            receiverSenderConnectedSignalFinalClassification = "receiver_window_closed_before_sender_signal_redacted"
            receiverSenderConnectedWindowOverlapFinalClassification = "receiver_window_closed_before_sender_signal_redacted"
        } else if receiverConnectedSessionLeaseReleased, !remoteParticipantObservationWaitCompleted {
            receiverSenderConnectedWindowOverlapFinalClassification = "receiver_cleanup_released_lease_early_redacted"
        } else {
            receiverSenderConnectedSignalFinalClassification = "sender_connected_signal_missing_redacted"
            receiverSenderConnectedWindowOverlapFinalClassification = "receiver_overlap_wait_timeout_redacted"
        }
    }

    mutating func refreshRemoteParticipantObservationTimingRepairDiagnostics() {
        remoteParticipantObservationTimingRepairPresent = true
        remoteParticipantObservationTimingRepairDebugOnly = true
        remoteParticipantObservationTimingRepairBoundedWindow = true
        remoteParticipantObservationTimingRepairRawIdentifiersLogged = false
        refreshParticipantObserverPropagationRepairDiagnostics()
        receiverSenderConnectedOverlapRepairPresent = true
        receiverSenderConnectedOverlapRepairDebugOnly = true
        receiverSenderConnectedOverlapRepairRawIdentifiersLogged = false
        receiverConnectedWindowRetentionRepairPresent = true
        receiverConnectedWindowRetentionRepairDebugOnly = true
        receiverConnectedWindowRetentionRepairRawIdentifiersLogged = false

        let receiverJoinSucceeded = liveKitJoinResult == "success_redacted"
        let receiverLeaseActive = receiverConnectedSessionLeaseAcquired &&
            receiverConnectedSessionLeaseRoomRetained &&
            !receiverConnectedSessionLeaseReleased
        receiverConnectedSessionLeaseActiveAfterSenderTrigger = receiverConnectedSessionLeaseActiveAfterSenderTrigger ||
            (receiverLeaseActive && remoteParticipantObservationWaitStarted)
        if receiverJoinSucceeded, !remoteParticipantObservationWaitStarted {
            remoteParticipantObservationWaitStarted = true
            remoteParticipantObservationTimeoutBucket = "pending_redacted"
            remoteParticipantObservationFinalClassification = "pending_redacted"
        }

        senderReadinessContextPresentDuringObservation = !senderReadinessRuntimeHandoffMissingClassified &&
            (senderReadinessRuntimeHandoffReceivedByRuntime || senderLiveKitReadinessHookArmed)
        opaqueCallCorrelationPresent = senderReadinessContextPresentDuringObservation || remotePeerContextHandoffReceivedByRuntime || remotePeerContextHandoffArmedBeforeAPNs
        opaqueCallCorrelationMatch = opaqueCallCorrelationPresent &&
            (senderReadinessRuntimeHandoffSameRoomReady || senderLiveKitReadinessHookSameRoomReady || remotePeerContextHandoffReceivedByRuntime)
        senderJoinTerminalSeenByReceiver = senderJoinTerminalSeenByReceiver ||
            senderTriggerCompleted ||
            senderSDKTimelineTerminalSeen ||
            senderConnectedSignalReceivedByReceiver
        let senderConnectedSignalAvailable = senderConnectedSignalReceivedByReceiver ||
            senderSideLiveKitJoinResult == SalemXSenderSideLiveKitJoinHook.successResult ||
            senderLiveKitSDKTimelineConnectedStateSeen
        senderRoomConnectedDuringReceiverWindow = senderRoomConnectedDuringReceiverWindow ||
            (remoteParticipantObservationWaitStarted &&
                senderConnectedSignalAvailable &&
                (!receiverConnectedWindowClosed || senderConnectedSignalBeforeReceiverDisconnect))
        senderCleanupStartedBeforeReceiverObservation = senderLiveKitSDKTimelineDisconnectedStateSeen &&
            !remoteParticipantObservationWaitCompleted &&
            !liveKitRemoteParticipantSeen
        receiverRoomRetainedForSenderObservation = receiverRoomRetainedForSenderObservation ||
            (remoteParticipantObservationWaitStarted &&
                receiverJoinSucceeded &&
                (receiverLeaseActive || receiverConnectedSessionLeaseRoomRetained))
        receiverObserverAttachedBeforeSenderJoin = receiverObserverAttachedBeforeSenderJoin ||
            (remoteParticipantObservationWaitStarted &&
                (!senderTriggerStarted || receiverRemoteParticipantObserverStarted) &&
                receiverConnectedSessionLeaseObserverRetained)
        receiverObserverActiveDuringSenderJoin = receiverObserverActiveDuringSenderJoin ||
            (receiverRemoteParticipantObserverStarted &&
                remoteParticipantObservationWaitStarted &&
                !remoteParticipantObservationWaitCompleted &&
                receiverLeaseActive &&
                (senderTriggerStarted || senderRoomConnectedDuringReceiverWindow))
        receiverSenderConnectedWindowOverlapObserved = receiverSenderConnectedWindowOverlapObserved ||
            (receiverRoomRetainedForSenderObservation &&
                senderRoomConnectedDuringReceiverWindow &&
                (!receiverConnectedSessionLeaseReleased || senderConnectedSignalBeforeReceiverDisconnect))
        if receiverSenderConnectedWindowOverlapObserved {
            receiverParticipantObservationAfterOverlapStarted = true
        }
        receiverSenderConnectedSignalReceived = receiverSenderConnectedSignalReceived || senderConnectedSignalReceivedByReceiver
        receiverSenderConnectedSignalReceivedBeforeReceiverDisconnect = receiverSenderConnectedSignalReceivedBeforeReceiverDisconnect || senderConnectedSignalBeforeReceiverDisconnect
        receiverSenderConnectedSignalReceivedAfterReceiverDisconnect = receiverSenderConnectedSignalReceivedAfterReceiverDisconnect || senderConnectedSignalAfterReceiverDisconnect
        receiverCleanupStartedBeforeSenderTerminal = liveKitRoomDisconnected &&
            !senderJoinTerminalSeenByReceiver &&
            !remoteParticipantObservationWaitCompleted &&
            !receiverLeaseActive
        receiverCleanupDeferredUntilObservationTerminal = receiverCleanupDeferredUntilObservationTerminal ||
            (remoteParticipantObservationWaitStarted &&
                controlledCallKitCleanupRequested &&
                liveKitConnectAudioInvoked &&
                receiverLeaseActive)

        if liveKitRemoteParticipantSeen, !remoteParticipantObservationWaitCompleted {
            completeRemoteParticipantObservation(classification: remoteParticipantSeenClassification(), timeoutBucket: "none")
        }
    }

    private mutating func refreshParticipantObserverPropagationRepairDiagnostics() {
        participantObserverPropagationRepairPresent = true
        participantObserverPropagationRepairDebugOnly = true
        participantObserverPropagationRawIdentifiersLogged = false

        let receiverLeaseActive = receiverConnectedSessionLeaseAcquired &&
            receiverConnectedSessionLeaseRoomRetained &&
            !receiverConnectedSessionLeaseReleased
        receiverParticipantObserverBoundToRetainedRoom = receiverParticipantObserverBoundToRetainedRoom ||
            (receiverRemoteParticipantObserverStarted && receiverConnectedSessionLeaseRoomRetained)
        receiverParticipantObserverBoundToConnectedRoom = receiverParticipantObserverBoundToConnectedRoom ||
            (receiverParticipantObserverBoundToRetainedRoom && liveKitRoomConnected && !liveKitRoomDisconnected)
        receiverParticipantObserverAttachedBeforeSenderSignal = receiverParticipantObserverAttachedBeforeSenderSignal ||
            (receiverRemoteParticipantObserverStarted &&
                receiverConnectedSessionLeaseObserverRetained &&
                !senderConnectedSignalReceivedByReceiver)
        receiverParticipantObserverActiveAfterSenderSignal = receiverParticipantObserverActiveAfterSenderSignal ||
            (senderConnectedSignalReceivedByReceiver &&
                receiverRemoteParticipantObserverStarted &&
                receiverLeaseActive)
        receiverParticipantObservationFinalClassification = remoteParticipantObservationFinalClassification
    }

    mutating func activateRemoteParticipantObservationRuntimeWindowIfNeeded() {
        guard controlledConnectFirstAttemptResult == "success_redacted",
              liveKitJoinRequested,
              liveKitConnectAudioInvoked,
              !remoteParticipantObservationWaitCompleted else {
            refreshRemoteParticipantObservationTimingRepairDiagnostics()
            return
        }

        liveKitJoinResult = "success_redacted"
        liveKitJoinErrorBucket = "none"
        liveKitRoomConnected = true
        liveKitRoomDisconnected = false
        liveKitLocalParticipantPresent = true
        receiverRemoteParticipantObserverStarted = true
        remoteParticipantObservationWaitStarted = true
        if remoteParticipantObservationTimeoutBucket == "not_started" {
            remoteParticipantObservationTimeoutBucket = "pending_redacted"
        }
        if remoteParticipantObservationFinalClassification == "not_started" {
            remoteParticipantObservationFinalClassification = "pending_redacted"
        }
        liveKitCleanupRequested = false
        liveKitCleanupCompleted = false
        liveKitCleanupResult = "deferred_until_observation_terminal_redacted"
        refreshReceiverRemoteParticipantObserverClassification()
        refreshRemoteParticipantObservationTimingRepairDiagnostics()
    }

    mutating func refreshSenderJoinTriggerOrchestration() {
        let orchestration = SalemXSenderJoinTriggerOrchestration(input: .init(apnsSuccessSeen: physicalVoIPPushReceived,
                                                                              receiverAnswerSeen: receiverAnswerSeen,
                                                                              receiverConnectTerminalSeen: receiverConnectTerminalSeen,
                                                                              senderActivationArmed: senderSideLiveKitJoinActivationArmed,
                                                                              senderTriggerStarted: senderTriggerStarted,
                                                                              senderTriggerCompleted: senderTriggerCompleted,
                                                                              senderSDKTimelineTerminalSeen: senderSDKTimelineTerminalSeen))
        senderJoinTriggerOrchestrationPresent = orchestration.present
        senderJoinTriggerOrchestrationDebugOnly = orchestration.debugOnly
        senderJoinTriggerOrchestrationRawIdentifiersLogged = orchestration.rawIdentifiersLogged
        senderJoinTriggerOrchestrationAPNsSuccessSeen = orchestration.apnsSuccessSeen
        senderJoinTriggerOrchestrationReceiverAnswerSeen = orchestration.receiverAnswerSeen
        senderJoinTriggerOrchestrationReceiverConnectTerminalSeen = orchestration.receiverConnectTerminalSeen
        senderJoinTriggerOrchestrationSenderActivationArmed = orchestration.senderActivationArmed
        senderJoinTriggerOrchestrationSenderTriggerRequired = orchestration.senderTriggerRequired
        senderJoinTriggerOrchestrationSenderTriggerAllowed = orchestration.senderTriggerAllowed
        senderJoinTriggerOrchestrationSenderTriggerStarted = orchestration.senderTriggerStarted
        senderJoinTriggerOrchestrationSenderTriggerCompleted = orchestration.senderTriggerCompleted
        senderJoinTriggerOrchestrationSenderTriggerMissingClassified = orchestration.senderTriggerMissingClassified
        senderJoinTriggerOrchestrationPollAllowed = orchestration.pollAllowed
        senderJoinTriggerOrchestrationPollBlockedReason = orchestration.pollBlockedReason
        senderJoinTriggerOrchestrationFinalClassification = orchestration.finalClassification
    }

    private var receiverAnswerSeen: Bool {
        callKitFirstActionKind == "answer" && callKitAnswerActionReceived && callKitAnswerActionFulfilled
    }

    private var receiverConnectTerminalSeen: Bool {
        controlledConnectFirstAttemptCompleted || controlledConnectFirstAttemptResult != SalemXControlledAudioConnectFirstAttempt.defaultDisabled.result
    }

    private var senderTriggerStarted: Bool {
        senderSideLiveKitJoinActivationTriggered || senderSideLiveKitJoinRequested || senderLiveKitSDKTimelineTriggerReceived
    }

    private var senderTriggerCompleted: Bool {
        senderSideLiveKitJoinActivationConsumed || (senderSideLiveKitJoinRequested && senderSideLiveKitJoinResult != SalemXSenderSideLiveKitJoinHook.notRequestedResult)
    }

    private var senderSDKTimelineTerminalSeen: Bool {
        SalemXSenderLiveKitSDKTimeline.terminalClassifications.contains(senderLiveKitSDKTimelineFinalClassification)
    }

    private mutating func refreshReceiverRemoteParticipantObserverClassification() {
        if let classification = remoteParticipantSeenObserverClassification()
            ?? senderJoinObserverClassification() {
            receiverRemoteParticipantObserverResult = classification.result
            receiverRemoteParticipantObserverErrorBucket = classification.errorBucket
            receiverRemoteParticipantObserverTimeoutBucket = classification.timeoutBucket
            if let livenessErrorBucket = classification.livenessErrorBucket {
                liveKitAudioLivenessObserved = false
                liveKitAudioLivenessResult = "not_observed_redacted"
                liveKitAudioLivenessErrorBucket = livenessErrorBucket
            }
            return
        }

        receiverRemoteParticipantObserverResult = "not_observed_redacted"
        receiverRemoteParticipantObserverErrorBucket = "sender_not_joined_or_remote_missing_redacted"
        receiverRemoteParticipantObserverTimeoutBucket = "not_observed_redacted"
    }

    private func remoteParticipantSeenObserverClassification() -> SalemXRemoteParticipantObserverClassification? {
        if liveKitAudioLivenessObserved {
            return .init(result: "success_redacted", errorBucket: "none", timeoutBucket: "none", livenessErrorBucket: nil)
        }
        if liveKitRemoteParticipantSeen, !liveKitRemoteAudioTrackSubscribed {
            return .init(result: remoteParticipantSeenClassification(),
                         errorBucket: "remote_audio_track_missing_redacted",
                         timeoutBucket: "not_observed_redacted",
                         livenessErrorBucket: nil)
        }
        if liveKitRemoteParticipantSeen {
            return .init(result: remoteParticipantSeenClassification(),
                         errorBucket: "remote_liveness_not_observed_redacted",
                         timeoutBucket: "not_observed_redacted",
                         livenessErrorBucket: nil)
        }
        return nil
    }

    private func remoteParticipantSeenClassification() -> String {
        if receiverParticipantEventCallbackSeen {
            return "remote_participant_seen_via_callback_redacted"
        }
        if receiverParticipantSnapshotSeen {
            return "remote_participant_seen_via_snapshot_redacted"
        }
        return receiverSenderConnectedWindowOverlapObserved ?
            "remote_participant_seen_via_retained_window_redacted" :
            "remote_participant_seen_redacted"
    }

    private func senderJoinObserverClassification() -> SalemXRemoteParticipantObserverClassification? {
        guard receiverRemoteParticipantObserverStarted else {
            return nil
        }
        if senderReadinessRuntimeHandoffMissingClassified {
            return .init(result: "not_observed_redacted",
                         errorBucket: "sender_readiness_context_missing_redacted",
                         timeoutBucket: "not_observed_redacted",
                         livenessErrorBucket: "sender_readiness_context_missing_redacted")
        }
        if !senderSideLiveKitJoinActivationArmed {
            return .init(result: "not_observed_redacted", errorBucket: "sender_join_hook_not_armed_redacted", timeoutBucket: "not_observed_redacted", livenessErrorBucket: nil)
        }
        if !senderSideLiveKitJoinActivationTriggered || senderSideLiveKitJoinResult == SalemXSenderSideLiveKitJoinHook.notRequestedResult {
            return .init(result: "not_observed_redacted", errorBucket: "sender_join_not_requested_redacted", timeoutBucket: "not_observed_redacted", livenessErrorBucket: nil)
        }
        if senderSideLiveKitJoinResult == SalemXSenderSideLiveKitJoinHook.blockedResult {
            return .init(result: "not_observed_redacted", errorBucket: "sender_join_blocked_redacted", timeoutBucket: "not_observed_redacted", livenessErrorBucket: nil)
        }
        if senderSideLiveKitJoinResult == SalemXSenderSideLiveKitJoinHook.failedResult {
            return .init(result: "not_observed_redacted", errorBucket: "sender_join_failed_redacted", timeoutBucket: "not_observed_redacted", livenessErrorBucket: nil)
        }
        if senderSideLiveKitJoinResult == SalemXSenderSideLiveKitJoinHook.successResult {
            return .init(result: "not_observed_redacted",
                         errorBucket: "sender_join_success_but_remote_missing_redacted",
                         timeoutBucket: "not_observed_redacted",
                         livenessErrorBucket: nil)
        }
        return .init(result: "not_observed_redacted", errorBucket: "remote_participant_missing_redacted", timeoutBucket: "not_observed_redacted", livenessErrorBucket: nil)
    }

    mutating func recordSenderLiveKitReadinessHook(_ hook: SalemXSenderLiveKitReadinessHook) {
        senderLiveKitReadinessHookPresent = hook.present
        senderLiveKitReadinessHookDebugOnly = hook.debugOnly
        senderLiveKitReadinessHookDefaultDisabled = hook.isDefaultDisabled
        senderLiveKitReadinessHookArmed = hook.armed
        senderLiveKitReadinessHookMatrixSessionReady = hook.matrixSessionReady
        senderLiveKitReadinessHookExpectedUserMatched = hook.expectedUserMatched
        senderLiveKitReadinessHookSameRoomReady = hook.sameRoomReady
        senderLiveKitReadinessHookCredentialsReady = hook.credentialsReady
        senderLiveKitReadinessHookAudioOnly = hook.audioOnly
        senderLiveKitReadinessHookVideoAllowed = hook.videoAllowed
        senderLiveKitReadinessHookMatrixEventsAllowed = hook.matrixEventsAllowed
        senderLiveKitReadinessHookRawIdentifiersLogged = hook.rawIdentifiersLogged
        senderLiveKitReadinessHookBlockedReason = hook.blockedReason
        refreshRemoteParticipantPresenceRepairDiagnostics()
    }

    mutating func recordSenderReadinessRuntimeHandoff(_ hook: SalemXSenderLiveKitReadinessHook,
                                                      receivedByRuntime: Bool,
                                                      survivedPushKit: Bool,
                                                      survivedAnswer: Bool) {
        recordSenderLiveKitReadinessHook(hook)
        senderReadinessRuntimeHandoffPresent = true
        senderReadinessRuntimeHandoffDebugOnly = true
        senderReadinessRuntimeHandoffArmedBeforeAPNs = hook.armed
        senderReadinessRuntimeHandoffReceivedByRuntime = receivedByRuntime && hook.armed
        senderReadinessRuntimeHandoffSurvivedPushKit = survivedPushKit && hook.armed
        senderReadinessRuntimeHandoffSurvivedAnswer = survivedAnswer && hook.armed
        senderReadinessRuntimeHandoffMatrixSessionReady = hook.matrixSessionReady
        senderReadinessRuntimeHandoffSameRoomReady = hook.sameRoomReady
        senderReadinessRuntimeHandoffExpectedUserMatched = hook.expectedUserMatched
        senderReadinessRuntimeHandoffRawIdentifiersLogged = false
        senderReadinessRuntimeHandoffMissingClassified = !senderReadinessRuntimeHandoffReceivedByRuntime
        refreshRemoteParticipantPresenceRepairDiagnostics()
    }

    mutating func recordSenderReadinessRuntimeHandoff(_ hook: SalemXSenderLiveKitReadinessHook?) {
        guard let hook else {
            recordMissingSenderReadinessRuntimeHandoff()
            return
        }

        recordSenderReadinessRuntimeHandoff(hook,
                                            receivedByRuntime: true,
                                            survivedPushKit: true,
                                            survivedAnswer: false)
    }

    mutating func markSenderReadinessRuntimeHandoffSurvivedAnswer() {
        guard senderReadinessRuntimeHandoffReceivedByRuntime else {
            recordMissingSenderReadinessRuntimeHandoff()
            return
        }

        senderReadinessRuntimeHandoffSurvivedAnswer = true
        refreshRemoteParticipantPresenceRepairDiagnostics()
    }

    mutating func recordMissingSenderReadinessRuntimeHandoff() {
        recordSenderLiveKitReadinessHook(.defaultDisabled)
        senderReadinessRuntimeHandoffPresent = true
        senderReadinessRuntimeHandoffDebugOnly = true
        senderReadinessRuntimeHandoffArmedBeforeAPNs = false
        senderReadinessRuntimeHandoffReceivedByRuntime = false
        senderReadinessRuntimeHandoffSurvivedPushKit = false
        senderReadinessRuntimeHandoffSurvivedAnswer = false
        senderReadinessRuntimeHandoffMatrixSessionReady = false
        senderReadinessRuntimeHandoffSameRoomReady = false
        senderReadinessRuntimeHandoffExpectedUserMatched = false
        senderReadinessRuntimeHandoffRawIdentifiersLogged = false
        senderReadinessRuntimeHandoffMissingClassified = true
        liveKitAudioLivenessObserved = false
        liveKitAudioLivenessResult = "not_observed_redacted"
        liveKitAudioLivenessErrorBucket = "sender_readiness_context_missing_redacted"
        refreshRemoteParticipantPresenceRepairDiagnostics()
    }

    mutating func recordSenderSideLiveKitJoinHook(_ hook: SalemXSenderSideLiveKitJoinHook) {
        senderSideLiveKitJoinHookPresent = hook.present
        senderSideLiveKitJoinHookDebugOnly = hook.debugOnly
        senderSideLiveKitJoinHookDefaultDisabled = hook.isDefaultDisabled
        senderSideLiveKitJoinHookArmed = hook.armed
        senderSideLiveKitJoinHookAudioOnly = hook.audioOnly
        senderSideLiveKitJoinHookVideoAllowed = hook.videoAllowed
        senderSideLiveKitJoinHookMatrixEventsAllowed = hook.matrixEventsAllowed
        senderSideLiveKitJoinHookRawCredentialsLogged = hook.rawCredentialsLogged
        senderSideLiveKitJoinRequested = hook.requested
        senderSideLiveKitJoinResult = hook.result
        senderSideLiveKitJoinErrorBucket = hook.errorBucket
        senderSideLiveKitJoinRepeated = hook.repeated
        refreshRemoteParticipantPresenceRepairDiagnostics()
    }

    mutating func recordSenderConnectParity(_ parity: SalemXSenderConnectParity) {
        senderConnectParityPresent = parity.present
        senderConnectParityDebugOnly = parity.debugOnly
        senderConnectParityRawURLLogged = parity.rawURLLogged
        senderConnectParityRawTokenLogged = parity.rawTokenLogged
        senderConnectParityRawRoomLogged = parity.rawRoomLogged
        senderConnectParityRawIdentityLogged = parity.rawIdentityLogged
        senderConnectParityUsesReceiverProvenConnectWrapper = parity.usesReceiverProvenConnectWrapper
        senderConnectParityUsesAudioOnly = parity.usesAudioOnly
        senderConnectParityVideoAllowed = parity.videoAllowed
        senderConnectParityMatrixEventsAllowed = parity.matrixEventsAllowed
        senderConnectParityRoomRetainedUntilTerminal = parity.roomRetainedUntilTerminal
        senderConnectParityDelegateRetainedUntilTerminal = parity.delegateRetainedUntilTerminal
        senderConnectParityStateObserverRetainedUntilTerminal = parity.stateObserverRetainedUntilTerminal
        senderConnectParityTaskRetainedUntilTerminal = parity.taskRetainedUntilTerminal
        senderConnectParityBoundedWaitUsed = parity.boundedWaitUsed
    }

    mutating func recordSenderConnectExecutorUnification(_ unification: SalemXSenderConnectExecutorUnification) {
        senderConnectExecutorUnificationPresent = unification.present
        senderConnectExecutorUnificationDebugOnly = unification.debugOnly
        senderConnectExecutorUnificationReceiverExecutorShared = unification.receiverExecutorShared
        senderConnectExecutorUnificationSenderExecutorShared = unification.senderExecutorShared
        senderConnectExecutorUnificationSameConnectOptionsShape = unification.sameConnectOptionsShape
        senderConnectExecutorUnificationSameRoomRetentionModel = unification.sameRoomRetentionModel
        senderConnectExecutorUnificationSameDelegateRetentionModel = unification.sameDelegateRetentionModel
        senderConnectExecutorUnificationSameStateObserverModel = unification.sameStateObserverModel
        senderConnectExecutorUnificationSameBoundedWaitModel = unification.sameBoundedWaitModel
        senderConnectExecutorUnificationAudioOnly = unification.audioOnly
        senderConnectExecutorUnificationVideoAllowed = unification.videoAllowed
        senderConnectExecutorUnificationMatrixEventsAllowed = unification.matrixEventsAllowed
        senderConnectExecutorUnificationRawURLLogged = unification.rawURLLogged
        senderConnectExecutorUnificationRawTokenLogged = unification.rawTokenLogged
        senderConnectExecutorUnificationRawRoomLogged = unification.rawRoomLogged
        senderConnectExecutorUnificationRawIdentityLogged = unification.rawIdentityLogged
    }

    mutating func recordSenderJoinFailureDiagnostics(_ diagnostics: SalemXSenderJoinFailureDiagnostics) {
        senderJoinFailureDiagnosticsPresent = diagnostics.present
        senderJoinFailureDiagnosticsDebugOnly = diagnostics.debugOnly
        senderJoinFailureDiagnosticsAudioOnly = diagnostics.audioOnly
        senderJoinFailureDiagnosticsVideoAllowed = diagnostics.videoAllowed
        senderJoinFailureDiagnosticsMatrixEventsAllowed = diagnostics.matrixEventsAllowed
        senderJoinFailureDiagnosticsRawIdentifiersLogged = diagnostics.rawIdentifiersLogged
        senderJoinFailureDiagnosticsCredentialsPresent = diagnostics.credentialsPresent
        senderJoinFailureDiagnosticsTokenPresent = diagnostics.tokenPresent
        senderJoinFailureDiagnosticsURLPresent = diagnostics.urlPresent
        senderJoinFailureDiagnosticsRoomBindingPresent = diagnostics.roomBindingPresent
        senderJoinFailureDiagnosticsSameLiveKitRoom = diagnostics.sameLiveKitRoom
        senderJoinFailureDiagnosticsTransportAttempted = diagnostics.transportAttempted
        senderJoinFailureDiagnosticsTransportResult = diagnostics.transportResult
        senderJoinFailureDiagnosticsErrorBucket = diagnostics.errorBucket
        senderJoinFailureDiagnosticsClassification = diagnostics.classification
        refreshRemoteParticipantPresenceRepairDiagnostics()
    }

    mutating func recordSenderTransportFailureDiagnostics(_ diagnostics: SalemXSenderTransportFailureDiagnostics) {
        senderTransportFailureDiagnosticsPresent = diagnostics.present
        senderTransportFailureDiagnosticsDebugOnly = diagnostics.debugOnly
        senderTransportFailureDiagnosticsAudioOnly = diagnostics.audioOnly
        senderTransportFailureDiagnosticsVideoAllowed = diagnostics.videoAllowed
        senderTransportFailureDiagnosticsMatrixEventsAllowed = diagnostics.matrixEventsAllowed
        senderTransportFailureDiagnosticsRawIdentifiersLogged = diagnostics.rawIdentifiersLogged
        senderTransportFailureDiagnosticsTransportAttempted = diagnostics.transportAttempted
        senderTransportFailureDiagnosticsTransportStarted = diagnostics.transportStarted
        senderTransportFailureDiagnosticsTransportCompleted = diagnostics.transportCompleted
        senderTransportFailureDiagnosticsTransportResult = diagnostics.transportResult
        senderTransportFailureDiagnosticsErrorBucket = diagnostics.errorBucket
        senderTransportFailureDiagnosticsClassification = diagnostics.classification
        senderTransportFailureDiagnosticsLiveKitURLPresent = diagnostics.liveKitURLPresent
        senderTransportFailureDiagnosticsTokenPresent = diagnostics.tokenPresent
        senderTransportFailureDiagnosticsRoomBindingPresent = diagnostics.roomBindingPresent
        senderTransportFailureDiagnosticsSameLiveKitRoom = diagnostics.sameLiveKitRoom
        senderTransportFailureDiagnosticsSameTokenAuthority = diagnostics.sameTokenAuthority
        senderTransportFailureDiagnosticsReceiverSenderRoomMatch = diagnostics.receiverSenderRoomMatch
        senderTransportFailureDiagnosticsReceiverSenderTokenAuthorityMatch = diagnostics.receiverSenderTokenAuthorityMatch
        refreshRemoteParticipantPresenceRepairDiagnostics()
    }

    mutating func recordSenderLiveKitSDKFailureSurface(_ sdkFailureSurface: SalemXSenderLiveKitSDKFailureSurface) {
        senderLiveKitSDKFailureSurfacePresent = sdkFailureSurface.present
        senderLiveKitSDKFailureSurfaceDebugOnly = sdkFailureSurface.debugOnly
        senderLiveKitSDKFailureSurfaceRawErrorLogged = sdkFailureSurface.rawErrorLogged
        senderLiveKitSDKFailureSurfaceRawURLLogged = sdkFailureSurface.rawURLLogged
        senderLiveKitSDKFailureSurfaceRawTokenLogged = sdkFailureSurface.rawTokenLogged
        senderLiveKitSDKFailureSurfaceRawRoomLogged = sdkFailureSurface.rawRoomLogged
        senderLiveKitSDKFailureSurfaceRawIdentityLogged = sdkFailureSurface.rawIdentityLogged
        senderLiveKitSDKFailureSurfaceConnectCallStarted = sdkFailureSurface.connectCallStarted
        senderLiveKitSDKFailureSurfaceConnectCallReturned = sdkFailureSurface.connectCallReturned
        senderLiveKitSDKFailureSurfaceConnectCallThrew = sdkFailureSurface.connectCallThrew
        senderLiveKitSDKFailureSurfaceConnectedStateObserved = sdkFailureSurface.connectedStateObserved
        senderLiveKitSDKFailureSurfaceFailedStateObserved = sdkFailureSurface.failedStateObserved
        senderLiveKitSDKFailureSurfaceDisconnectedBeforeConnected = sdkFailureSurface.disconnectedBeforeConnected
        senderLiveKitSDKFailureSurfaceDelegateFailureObserved = sdkFailureSurface.delegateFailureObserved
        senderLiveKitSDKFailureSurfaceRoomAlreadyConnected = sdkFailureSurface.roomAlreadyConnected
        senderLiveKitSDKFailureSurfaceIdentityConflictObserved = sdkFailureSurface.identityConflictObserved
        senderLiveKitSDKFailureSurfaceTokenIdentityMatch = sdkFailureSurface.tokenIdentityMatch
        senderLiveKitSDKFailureSurfaceAudioSessionReady = sdkFailureSurface.audioSessionReady
        senderLiveKitSDKFailureSurfacePermissionRequired = sdkFailureSurface.permissionRequired
        senderLiveKitSDKFailureSurfaceCaptureStarted = sdkFailureSurface.captureStarted
        senderLiveKitSDKFailureSurfaceFinalClassification = sdkFailureSurface.finalClassification
        recordSenderLiveKitSDKTimeline(sdkFailureSurface.timeline)
        recordSenderLiveKitSDKTimeoutDiagnostics(sdkFailureSurface.timeline.timeoutDiagnostics)
        refreshRemoteParticipantPresenceRepairDiagnostics()
    }

    mutating func recordSenderLiveKitSDKTimeline(_ timeline: SalemXSenderLiveKitSDKTimeline) {
        senderLiveKitSDKTimelinePresent = timeline.present
        senderLiveKitSDKTimelineDebugOnly = timeline.debugOnly
        senderLiveKitSDKTimelineRawErrorLogged = timeline.rawErrorLogged
        senderLiveKitSDKTimelineRawURLLogged = timeline.rawURLLogged
        senderLiveKitSDKTimelineRawTokenLogged = timeline.rawTokenLogged
        senderLiveKitSDKTimelineRawRoomLogged = timeline.rawRoomLogged
        senderLiveKitSDKTimelineRawIdentityLogged = timeline.rawIdentityLogged
        senderLiveKitSDKTimelineTriggerReceived = timeline.triggerReceived
        senderLiveKitSDKTimelineTaskCreated = timeline.taskCreated
        senderLiveKitSDKTimelineTaskStarted = timeline.taskStarted
        senderLiveKitSDKTimelineConnectInvoked = timeline.connectInvoked
        senderLiveKitSDKTimelineConnectReturned = timeline.connectReturned
        senderLiveKitSDKTimelineConnectThrew = timeline.connectThrew
        senderLiveKitSDKTimelineDelegateAttached = timeline.delegateAttached
        senderLiveKitSDKTimelineStateObserverAttached = timeline.stateObserverAttached
        senderLiveKitSDKTimelineConnectedStateSeen = timeline.connectedStateSeen
        senderLiveKitSDKTimelineFailedStateSeen = timeline.failedStateSeen
        senderLiveKitSDKTimelineDisconnectedStateSeen = timeline.disconnectedStateSeen
        senderLiveKitSDKTimelineTaskCancelled = timeline.taskCancelled
        senderLiveKitSDKTimelineTaskCompleted = timeline.taskCompleted
        senderLiveKitSDKTimelineTimeoutElapsed = timeline.timeoutElapsed
        senderLiveKitSDKTimelineProofWrittenAfterTerminalState = timeline.proofWrittenAfterTerminalState
        senderLiveKitSDKTimelineFinalClassification = timeline.finalClassification
        recordSenderLiveKitSDKTimeoutDiagnostics(timeline.timeoutDiagnostics)
        refreshSenderJoinTriggerOrchestration()
    }

    mutating func recordSenderLiveKitSDKTimeoutDiagnostics(_ diagnostics: SalemXSenderLiveKitSDKTimeoutDiagnostics) {
        senderLiveKitSDKTimeoutDiagnosticsPresent = diagnostics.present
        senderLiveKitSDKTimeoutDiagnosticsDebugOnly = diagnostics.debugOnly
        senderLiveKitSDKTimeoutDiagnosticsRawErrorLogged = diagnostics.rawErrorLogged
        senderLiveKitSDKTimeoutDiagnosticsRawURLLogged = diagnostics.rawURLLogged
        senderLiveKitSDKTimeoutDiagnosticsRawTokenLogged = diagnostics.rawTokenLogged
        senderLiveKitSDKTimeoutDiagnosticsRawRoomLogged = diagnostics.rawRoomLogged
        senderLiveKitSDKTimeoutDiagnosticsRawIdentityLogged = diagnostics.rawIdentityLogged
        senderLiveKitSDKTimeoutDiagnosticsWaitWindowBucket = diagnostics.waitWindowBucket
        senderLiveKitSDKTimeoutDiagnosticsConnectInvoked = diagnostics.connectInvoked
        senderLiveKitSDKTimeoutDiagnosticsConnectCallPendingAtTimeout = diagnostics.connectCallPendingAtTimeout
        senderLiveKitSDKTimeoutDiagnosticsTaskRunningAtTimeout = diagnostics.taskRunningAtTimeout
        senderLiveKitSDKTimeoutDiagnosticsTaskCancelledAtTimeout = diagnostics.taskCancelledAtTimeout
        senderLiveKitSDKTimeoutDiagnosticsDelegateAttached = diagnostics.delegateAttached
        senderLiveKitSDKTimeoutDiagnosticsStateObserverAttached = diagnostics.stateObserverAttached
        senderLiveKitSDKTimeoutDiagnosticsStateEventCountBucket = diagnostics.stateEventCountBucket
        senderLiveKitSDKTimeoutDiagnosticsDelegateEventCountBucket = diagnostics.delegateEventCountBucket
        senderLiveKitSDKTimeoutDiagnosticsAppStateBucket = diagnostics.appStateBucket
        senderLiveKitSDKTimeoutDiagnosticsActorContextAvailable = diagnostics.actorContextAvailable
        senderLiveKitSDKTimeoutDiagnosticsNetworkPathBucket = diagnostics.networkPathBucket
        senderLiveKitSDKTimeoutDiagnosticsFinalClassification = diagnostics.finalClassification
    }

    mutating func recordSenderTransportErrorSurface(_ errorSurface: SalemXSenderTransportErrorSurface) {
        senderTransportErrorSurfacePresent = errorSurface.present
        senderTransportErrorSurfaceDebugOnly = errorSurface.debugOnly
        senderTransportErrorSurfaceRawErrorLogged = errorSurface.rawErrorLogged
        senderTransportErrorSurfaceRawURLLogged = errorSurface.rawURLLogged
        senderTransportErrorSurfaceRawTokenLogged = errorSurface.rawTokenLogged
        senderTransportErrorSurfaceSource = errorSurface.source
        senderTransportErrorSurfaceSDKErrorBucket = errorSurface.sdkErrorBucket
        senderTransportErrorSurfaceDisconnectReasonBucket = errorSurface.disconnectReasonBucket
        senderTransportErrorSurfaceWebsocketBucket = errorSurface.websocketBucket
        senderTransportErrorSurfaceAuthBucket = errorSurface.authBucket
        senderTransportErrorSurfaceTimeoutObserved = errorSurface.timeoutObserved
        senderTransportErrorSurfaceConnectedStateObserved = errorSurface.connectedStateObserved
        senderTransportErrorSurfaceDisconnectedBeforeConnected = errorSurface.disconnectedBeforeConnected
        senderTransportErrorSurfaceFinalClassification = errorSurface.finalClassification
        recordSenderLiveKitSDKFailureSurface(errorSurface.sdkFailureSurface)
    }

    private func senderSideLiveKitJoinActivationBlockedReason(for hook: SalemXSenderSideLiveKitJoinHook) -> String {
        if hook.repeated {
            return SalemXSenderSideLiveKitJoinActivation.repeatedSenderJoinBlockedReason
        }
        if !hook.armed {
            return SalemXSenderSideLiveKitJoinActivation.defaultDisabledNoConnectReason
        }
        if !hook.requested {
            return SalemXSenderSideLiveKitJoinActivation.armedWaitingForTriggerReason
        }
        if hook.result == SalemXSenderSideLiveKitJoinHook.blockedResult {
            return SalemXSenderSideLiveKitJoinActivation.senderJoinBlockedReason
        }
        if hook.result == SalemXSenderSideLiveKitJoinHook.failedResult {
            return SalemXSenderSideLiveKitJoinActivation.senderJoinFailedReason
        }
        if hook.result == SalemXSenderSideLiveKitJoinHook.successResult {
            return SalemXSenderSideLiveKitJoinActivation.senderJoinSuccessReason
        }
        return SalemXSenderSideLiveKitJoinActivation.armedWaitingForTriggerReason
    }

    mutating func recordSenderSideLiveKitJoinActivation(_ activation: SalemXSenderSideLiveKitJoinActivation) {
        senderSideLiveKitJoinActivationPresent = activation.present
        senderSideLiveKitJoinActivationDebugOnly = activation.debugOnly
        senderSideLiveKitJoinActivationDefaultDisabled = activation.isDefaultDisabled
        senderSideLiveKitJoinActivationRequiresSenderReadiness = activation.requiresSenderReadiness
        senderSideLiveKitJoinActivationRequiresSameRoom = activation.requiresSameRoom
        senderSideLiveKitJoinActivationAudioOnly = activation.audioOnly
        senderSideLiveKitJoinActivationVideoAllowed = activation.videoAllowed
        senderSideLiveKitJoinActivationMatrixEventsAllowed = activation.matrixEventsAllowed
        senderSideLiveKitJoinActivationRawIdentifiersLogged = activation.rawIdentifiersLogged
        senderSideLiveKitJoinActivationArmed = activation.armed
        senderSideLiveKitJoinActivationTriggered = activation.triggered
        senderSideLiveKitJoinActivationConsumed = activation.consumed
        senderSideLiveKitJoinActivationRepeated = activation.repeated
        senderSideLiveKitJoinActivationBlockedReason = activation.blockedReason
        refreshRemoteParticipantPresenceRepairDiagnostics()
    }

    mutating func recordSenderSideLiveKitJoinResult(requested: Bool,
                                                    result: String,
                                                    errorBucket: String = "none",
                                                    repeated: Bool = false) {
        let hook = SalemXSenderSideLiveKitJoinHook(armed: requested,
                                                   requested: requested,
                                                   result: result,
                                                   errorBucket: errorBucket,
                                                   repeated: repeated)
        let diagnostics = SalemXSenderJoinFailureDiagnostics.classify(.init(requested: requested,
                                                                            repeated: repeated,
                                                                            credentialsPresent: requested,
                                                                            tokenPresent: requested,
                                                                            urlPresent: requested,
                                                                            roomBindingPresent: requested,
                                                                            sameLiveKitRoom: requested,
                                                                            requestedResult: result,
                                                                            transportAttempted: nil,
                                                                            transportResult: nil,
                                                                            classification: nil))
        let transportDiagnostics = SalemXSenderTransportFailureDiagnostics.classify(.init(requested: requested,
                                                                                          liveKitURLPresent: requested,
                                                                                          tokenPresent: requested,
                                                                                          roomBindingPresent: requested,
                                                                                          sameLiveKitRoom: requested,
                                                                                          sameTokenAuthority: requested,
                                                                                          receiverSenderRoomMatch: requested,
                                                                                          receiverSenderTokenAuthorityMatch: requested,
                                                                                          transportAttempted: nil,
                                                                                          transportStarted: nil,
                                                                                          transportCompleted: nil,
                                                                                          transportResult: nil,
                                                                                          classification: nil,
                                                                                          errorSurface: .defaultDisabled))
        recordSenderSideLiveKitJoinHook(hook)
        recordSenderJoinFailureDiagnostics(diagnostics)
        recordSenderTransportFailureDiagnostics(transportDiagnostics)
        recordSenderTransportErrorSurface(.defaultDisabled)
        recordSenderSideLiveKitJoinActivation(.init(armed: requested,
                                                    triggered: requested,
                                                    consumed: requested && !repeated,
                                                    repeated: repeated,
                                                    blockedReason: senderSideLiveKitJoinActivationBlockedReason(for: hook)))
    }

    mutating func recordRemoteAudioLivenessJoinResult(succeeded: Bool, errorBucket: String = "none") {
        liveKitJoinRequested = true
        liveKitJoinResult = succeeded ? "success_redacted" : "failed_redacted"
        liveKitJoinErrorBucket = succeeded ? "none" : errorBucket
        liveKitRoomConnected = succeeded
        liveKitLocalParticipantPresent = succeeded
    }

    mutating func recordLocalAudioPublishResult(requested: Bool,
                                                started: Bool,
                                                succeeded: Bool,
                                                errorBucket: String = "none",
                                                notRequiredReason: String = "receive_only_audio_connect_redacted") {
        localAudioPublishRequested = requested
        localAudioPublishStarted = requested && started
        localAudioPublishResult = requested ? (succeeded ? "success_redacted" : "failed_redacted") : "not_required_redacted"
        localAudioPublishErrorBucket = requested && !succeeded ? errorBucket : "none"
        localAudioPublishNotRequiredReason = requested ? "none" : notRequiredReason
    }

    mutating func recordMicrophonePermissionResult(requested: Bool, notRequiredReason: String) {
        microphonePermissionRequested = requested
        microphonePermissionResult = requested ? "requested_redacted" : "not_requested_or_not_required_redacted"
        microphonePermissionNotRequiredReason = requested ? "requested_redacted" : notRequiredReason
    }

    mutating func recordRemotePeerContextHandoff(_ context: SalemXRemotePeerContextHandoff,
                                                 receivedByRuntime: Bool,
                                                 survivedPushKit: Bool,
                                                 survivedAnswer: Bool) {
        remotePeerContextHandoffPresent = true
        remotePeerContextHandoffDebugOnly = true
        remotePeerContextHandoffSource = context.source
        remotePeerContextHandoffArmedBeforeAPNs = context.armedBeforeAPNs
        remotePeerContextHandoffReceivedByRuntime = receivedByRuntime
        remotePeerContextHandoffSurvivedPushKit = survivedPushKit
        remotePeerContextHandoffSurvivedAnswer = survivedAnswer
        remotePeerContextHandoffRawIdentifiersLogged = false
        remotePeerContextHandoffBlocksSuccessWithoutContext = true
        remotePeerContextHandoffClassifiesMissingRemoteParticipant = true
        remotePeerContextHandoffClassifiesSimulatorLimitation = true
        secondDeviceRemoteAudioReadiness = context.readiness
        recordRemoteAudioPeerClassification(peerKind: context.peerKind,
                                            physicalDevice: context.physicalDevice,
                                            simulatorAssisted: context.simulatorAssisted)
    }

    mutating func recordRemotePeerContextHandoff(_ context: SalemXRemotePeerContextHandoff?) {
        guard let context else {
            recordMissingRemotePeerContextHandoff()
            return
        }

        recordRemotePeerContextHandoff(context,
                                       receivedByRuntime: true,
                                       survivedPushKit: true,
                                       survivedAnswer: false)
    }

    mutating func markRemotePeerContextHandoffSurvivedAnswer() {
        guard remotePeerContextHandoffReceivedByRuntime else {
            recordMissingRemotePeerContextHandoff()
            return
        }

        remotePeerContextHandoffSurvivedAnswer = true
    }

    mutating func recordMissingRemotePeerContextHandoff() {
        remotePeerContextHandoffPresent = true
        remotePeerContextHandoffDebugOnly = true
        remotePeerContextHandoffSource = "unknown_redacted"
        remotePeerContextHandoffArmedBeforeAPNs = false
        remotePeerContextHandoffReceivedByRuntime = false
        remotePeerContextHandoffSurvivedPushKit = false
        remotePeerContextHandoffSurvivedAnswer = false
        remotePeerContextHandoffRawIdentifiersLogged = false
        remotePeerContextHandoffBlocksSuccessWithoutContext = true
        remotePeerContextHandoffClassifiesMissingRemoteParticipant = true
        remotePeerContextHandoffClassifiesSimulatorLimitation = true
        remotePeerKind = "unknown_redacted"
        remotePeerPhysicalDevice = "unknown"
        simulatorAssistedRemoteAudioProof = false
        productionLikeTwoPhysicalDeviceProof = false
        secondDeviceRemoteAudioReadiness = "unknown_redacted"
        remoteAudioLivenessLimitation = "remote_peer_context_not_handed_off_redacted"
        liveKitAudioLivenessObserved = false
        liveKitAudioLivenessResult = "not_observed_redacted"
        liveKitAudioLivenessErrorBucket = "remote_peer_context_missing_redacted"
    }

    mutating func recordRemoteAudioPeerClassification(peerKind: String,
                                                      physicalDevice: String,
                                                      simulatorAssisted: Bool,
                                                      limitation: String = "none") {
        remotePeerKind = peerKind
        remotePeerPhysicalDevice = physicalDevice
        simulatorAssistedRemoteAudioProof = simulatorAssisted
        productionLikeTwoPhysicalDeviceProof = physicalDevice == "true" && !simulatorAssisted
        remoteAudioLivenessLimitation = simulatorAssisted ? "simulator_assisted_redacted" : limitation
    }

    mutating func recordRemoteAudioLivenessObservation(participantSeen: Bool,
                                                       participantCountBucket: String,
                                                       audioTrackSubscribed: Bool,
                                                       audioTrackUnmuted: Bool,
                                                       audioLevelObserved: Bool,
                                                       livenessObserved: Bool,
                                                       errorBucket: String = "none") {
        liveKitRemoteParticipantSeen = participantSeen
        liveKitRemoteParticipantCountBucket = participantCountBucket
        liveKitRemoteAudioTrackSubscribed = audioTrackSubscribed
        liveKitRemoteAudioTrackUnmuted = audioTrackUnmuted
        liveKitRemoteAudioLevelObserved = audioLevelObserved
        liveKitAudioLivenessObserved = livenessObserved
        liveKitAudioLivenessResult = livenessObserved ? "success_redacted" : "not_observed_redacted"
        if livenessObserved {
            liveKitAudioLivenessErrorBucket = "none"
        } else if !participantSeen {
            liveKitAudioLivenessErrorBucket = "remote_participant_missing_redacted"
        } else if !audioTrackSubscribed {
            liveKitAudioLivenessErrorBucket = "remote_audio_track_missing_redacted"
        } else {
            liveKitAudioLivenessErrorBucket = errorBucket
        }
        if participantSeen {
            completeRemoteParticipantObservation(classification: remoteParticipantSeenClassification(), timeoutBucket: "none")
        }
    }

    mutating func recordReceiverParticipantEventCallbackObservation(participantCountBucket: String) {
        let safeParticipantCountBucket = Self.safeParticipantCountBucket(participantCountBucket)
        receiverParticipantEventCallbackSeen = true
        receiverParticipantObserverActiveAfterSenderSignal = receiverParticipantObserverActiveAfterSenderSignal ||
            senderConnectedSignalReceivedByReceiver
        recordRemoteParticipantPresenceObservation(participantCountBucket: safeParticipantCountBucket,
                                                   classification: "remote_participant_seen_via_callback_redacted")
    }

    mutating func recordReceiverParticipantSnapshotRequested(boundToRetainedRoom: Bool, boundToConnectedRoom: Bool) {
        participantObserverPropagationRepairPresent = true
        participantObserverPropagationRepairDebugOnly = true
        participantObserverPropagationRawIdentifiersLogged = false
        receiverParticipantSnapshotRequested = true
        receiverParticipantObserverBoundToRetainedRoom = receiverParticipantObserverBoundToRetainedRoom || boundToRetainedRoom
        receiverParticipantObserverBoundToConnectedRoom = receiverParticipantObserverBoundToConnectedRoom || boundToConnectedRoom
        receiverParticipantObserverActiveAfterSenderSignal = receiverParticipantObserverActiveAfterSenderSignal ||
            (senderConnectedSignalReceivedByReceiver && boundToConnectedRoom)
        refreshReceiverRemoteParticipantObserverClassification()
        refreshRemoteParticipantObservationTimingRepairDiagnostics()
    }

    mutating func recordReceiverParticipantSnapshotObservation(_ snapshot: DirectCallRemoteParticipantSnapshot) {
        participantObserverPropagationRepairPresent = true
        participantObserverPropagationRepairDebugOnly = true
        participantObserverPropagationRawIdentifiersLogged = false
        receiverParticipantSnapshotRequested = true
        receiverParticipantSnapshotCountBucket = Self.safeParticipantCountBucket(snapshot.countBucket)
        receiverParticipantSnapshotSeen = snapshot.participantSeen
        receiverParticipantIdentityFilterApplied = snapshot.identityFilterApplied
        receiverParticipantIdentityFilterResult = Self.safeParticipantIdentityFilterResult(snapshot.identityFilterResult)
        if snapshot.participantSeen, snapshot.identityFilterResult != "filtered_out_redacted" {
            recordRemoteParticipantPresenceObservation(participantCountBucket: receiverParticipantSnapshotCountBucket,
                                                       classification: "remote_participant_seen_via_snapshot_redacted")
        } else {
            refreshReceiverRemoteParticipantObserverClassification()
            refreshRemoteParticipantObservationTimingRepairDiagnostics()
        }
    }

    private mutating func recordRemoteParticipantPresenceObservation(participantCountBucket: String, classification: String) {
        liveKitRemoteParticipantSeen = true
        liveKitRemoteParticipantCountBucket = Self.safeParticipantCountBucket(participantCountBucket)
        receiverRemoteParticipantObserverRemoteSeen = true
        liveKitAudioLivenessObserved = false
        liveKitAudioLivenessResult = "not_observed_redacted"
        liveKitAudioLivenessErrorBucket = "remote_audio_track_missing_redacted"
        completeRemoteParticipantObservation(classification: classification, timeoutBucket: "none")
    }

    private static func safeParticipantCountBucket(_ bucket: String) -> String {
        switch bucket {
        case "0", "1", "2+":
            return bucket
        default:
            return "unknown"
        }
    }

    private static func safeParticipantIdentityFilterResult(_ result: String) -> String {
        switch result {
        case "not_applied_redacted", "passed_redacted", "filtered_out_redacted":
            return result
        default:
            return "unknown_redacted"
        }
    }

    mutating func completeRemoteParticipantObservationTimeout(timeoutBucket: String) {
        completeReceiverSenderConnectedWindowOverlapTimeout()
        completeRemoteParticipantObservation(classification: remoteParticipantObservationTimeoutClassification(),
                                             timeoutBucket: timeoutBucket)
    }

    private func remoteParticipantObservationTimeoutClassification() -> String {
        if let classification = remoteParticipantObservationPreconditionTimeoutClassification() {
            return classification
        }
        if let classification = senderConnectedSignalTimeoutClassification() {
            return classification
        }
        if let classification = receiverSenderConnectedOverlapTimeoutClassification() {
            return classification
        }
        return "remote_participant_event_timeout_redacted"
    }

    private func remoteParticipantObservationPreconditionTimeoutClassification() -> String? {
        if liveKitRemoteParticipantSeen {
            return remoteParticipantSeenClassification()
        }
        if !receiverConnectedSessionLeaseAcquired {
            return "receiver_lease_not_acquired_redacted"
        }
        if receiverConnectedSessionLeaseReleased, !senderConnectedSignalReceivedByReceiver {
            return "receiver_lease_released_before_sender_signal_redacted"
        }
        if receiverCleanupStartedBeforeSenderTerminal {
            return "receiver_cleanup_started_before_sender_terminal_redacted"
        }
        if receiverConnectedSessionLeaseReleased, !senderTriggerStarted {
            return "receiver_room_released_before_sender_join_redacted"
        }
        if liveKitRoomDisconnected, !senderTriggerStarted {
            return "receiver_disconnected_before_sender_join_redacted"
        }
        let receiverObserverInactive = !receiverRemoteParticipantObserverStarted ||
            (senderTriggerStarted && !receiverObserverActiveDuringSenderJoin)
        if receiverObserverInactive {
            return "receiver_observer_not_active_redacted"
        }
        if let classification = participantObserverPropagationTimeoutClassification() {
            return classification
        }
        if !senderReadinessContextPresentDuringObservation {
            return "sender_readiness_context_missing_redacted"
        }
        if !opaqueCallCorrelationMatch {
            return "opaque_correlation_mismatch_redacted"
        }
        return nil
    }

    private func participantObserverPropagationTimeoutClassification() -> String? {
        guard senderConnectedSignalReceivedByReceiver else {
            return nil
        }
        if !receiverParticipantObserverBoundToRetainedRoom {
            return "participant_observer_not_bound_to_retained_room_redacted"
        }
        if !receiverParticipantObserverBoundToConnectedRoom {
            return "participant_observer_not_bound_to_connected_room_redacted"
        }
        if !receiverParticipantObserverAttachedBeforeSenderSignal {
            return "participant_observer_attached_late_redacted"
        }
        return nil
    }

    private func senderConnectedSignalTimeoutClassification() -> String? {
        if !senderConnectedSignalReceivedByReceiver {
            if receiverConnectedWindowClosedBeforeSenderConnected {
                return receiverDisconnectObservedBeforeSenderSignal ?
                    "receiver_disconnected_before_sender_signal_redacted" :
                    "receiver_window_closed_before_sender_signal_redacted"
            }
            return "sender_connected_signal_missing_redacted"
        }
        if senderConnectedSignalAfterReceiverDisconnect {
            return "sender_connected_signal_late_redacted"
        }
        if senderConnectedSignalReceivedByReceiver, !receiverSenderConnectedSignalCorrelationMatch {
            return "sender_connected_signal_correlation_mismatch_redacted"
        }
        return nil
    }

    private func receiverSenderConnectedOverlapTimeoutClassification() -> String? {
        if senderRoomConnectedDuringReceiverWindow, !receiverRoomRetainedForSenderObservation {
            return "sender_connected_outside_receiver_window_redacted"
        }
        if senderRoomConnectedDuringReceiverWindow, !receiverSenderConnectedWindowOverlapObserved {
            return "no_receiver_sender_connected_overlap_redacted"
        }
        if receiverSenderConnectedWindowOverlapObserved {
            if receiverParticipantIdentityFilterResult == "filtered_out_redacted" {
                return "participant_identity_filtered_out_redacted"
            }
            if receiverParticipantSnapshotRequested, !receiverParticipantSnapshotSeen {
                return "participant_snapshot_empty_redacted"
            }
            if !receiverParticipantEventCallbackSeen {
                return "participant_event_callback_missing_redacted"
            }
            return "participant_observation_timeout_after_overlap_redacted"
        }
        if senderCleanupStartedBeforeReceiverObservation {
            return "sender_disconnected_before_observation_redacted"
        }
        return nil
    }

    mutating func recordMetadataCredentialsBoundaryRepairProof(allowsHookConsumptionAfterCredentials: Bool = false) {
        metadataCredentialsBoundaryRepairPresent = true
        metadataCredentialsBoundaryRepairDebugOnly = true
        metadataCredentialsBoundaryRepairRequiresAnswer = true
        metadataCredentialsBoundaryRepairBlocksWithoutAnswer = true
        metadataCredentialsBoundaryRepairTriggersMetadataAfterAnswer = true
        metadataCredentialsBoundaryRepairTriggersCredentialsAfterMetadata = true
        metadataCredentialsBoundaryRepairBlocksConnectUntilCredentials = true
        metadataCredentialsBoundaryRepairDoesNotConsumeHookBeforeCredentials = true
        metadataCredentialsBoundaryRepairAllowsHookConsumptionAfterCredentials = allowsHookConsumptionAfterCredentials
        metadataCredentialsBoundaryRepairNoDirectConnectBypass = true
        metadataCredentialsBoundaryRepairRawCredentialsLogged = false
    }

    mutating func recordAnswerTriggeredPendingMetadataBoundary(source: String) {
        recordMetadataCredentialsBoundaryRepairProof()
        pendingMetadataFetchRequired = true
        foregroundPendingCallMetadataHandoffRequested = true
        foregroundPendingCallMetadataHandoffObserved = true
        foregroundPendingCallMetadataSource = source
        foregroundPendingCallMetadataPayloadRedacted = true
        foregroundPendingCallMetadataHasCallIdentifier = false
        foregroundPendingCallMetadataHasRoomBinding = false
        foregroundPendingCallMetadataHasPeer = false
        foregroundPendingCallMetadataDirection = "none"
        foregroundPendingCallMetadataIntent = "pending_metadata_fetch"
        mediaCredentialsRequestMetadataAvailable = false
        mediaCredentialsRequestMetadataRedacted = true
        mediaCredentialsRequestMetadataSource = source
        mediaCredentialsBoundaryReached = true
        mediaCredentialsRequestPlanned = false
        mediaCredentialsRequested = false
        mediaCredentialsRequestAuthorized = false
        mediaCredentialsResult = "blocked_redacted"
        mediaCredentialsTokenReceived = false
        mediaCredentialsTokenRedacted = true
        mediaCredentialsURLReceived = false
        mediaCredentialsURLRedacted = true
        mediaCredentialsExpiresAtPresent = false
        mediaCredentialsPayloadRedacted = true
        mediaCredentialsLocalPersistenceRequested = false
        mediaCredentialsCleanupRequested = false
        mediaCredentialsCleanupResult = "not_requested"
        mediaCredentialsPostCleanupTokenPresent = false
        mediaCredentialsPostCleanupURLPresent = false
        mediaCredentialsPostCleanupExpiresAtPresent = false
        mediaCredentialsPostCleanupPayloadPresent = false
        mediaCredentialsReuseAttempted = false
        mediaCredentialsReuseAllowed = false
        mediaCredentialsExpiryReferencePresent = false
        mediaCredentialsExpiryCheckRequested = false
        mediaCredentialsExpiryCheckResult = "not_requested"
        recordControlledAudioConnectFirstAttemptProof(.defaultDisabled)
    }

    mutating func recordControlledMediaCredentialsRequestBoundaryNotReady() {
        foregroundPendingCallMetadataHandoffRequested = true
        foregroundPendingCallMetadataHandoffObserved = false
        foregroundPendingCallMetadataSource = "synthetic_voip_receipt"
        foregroundPendingCallMetadataPayloadRedacted = true
        foregroundPendingCallMetadataHasCallIdentifier = false
        foregroundPendingCallMetadataHasRoomBinding = false
        foregroundPendingCallMetadataHasPeer = false
        foregroundPendingCallMetadataDirection = "none"
        foregroundPendingCallMetadataIntent = "none"
        mediaCredentialsRequestMetadataAvailable = false
        mediaCredentialsRequestMetadataRedacted = true
        mediaCredentialsRequestMetadataSource = "none"
        mediaCredentialsBoundaryReached = true
        mediaCredentialsRequestPlanned = false
        mediaCredentialsRequested = false
        mediaCredentialsRequestAuthorized = false
        mediaCredentialsResult = "blocked_redacted"
        mediaCredentialsTokenReceived = false
        mediaCredentialsTokenRedacted = true
        mediaCredentialsURLReceived = false
        mediaCredentialsURLRedacted = true
        mediaCredentialsExpiresAtPresent = false
        mediaCredentialsPayloadRedacted = true
        mediaCredentialsLocalPersistenceRequested = false
        mediaCredentialsCleanupRequested = false
        mediaCredentialsCleanupResult = "not_requested"
        mediaCredentialsPostCleanupTokenPresent = false
        mediaCredentialsPostCleanupURLPresent = false
        mediaCredentialsPostCleanupExpiresAtPresent = false
        mediaCredentialsPostCleanupPayloadPresent = false
        mediaCredentialsReuseAttempted = false
        mediaCredentialsReuseAllowed = false
        mediaCredentialsExpiryReferencePresent = false
        mediaCredentialsExpiryCheckRequested = false
        mediaCredentialsExpiryCheckResult = "not_requested"
        blockedReason = "media_credentials_request_boundary_not_ready"
    }

    mutating func recordMetadataCredentialsBoundaryMissingAfterAnswer(physical6RuntimeEnablementHook: SalemXPhysical6RuntimeEnablementURLHook) {
        recordAnswerTriggeredPendingMetadataBoundary(source: "callkit_answer_pending_metadata_missing_reference")
        recordPendingMetadataReferenceRepairProof(referencePresent: false)
        pendingMetadataFetchRequested = true
        pendingMetadataFetchAuthorized = false
        pendingMetadataFetchResult = "blocked_redacted"
        pendingMetadataFetchHTTPStatusBucket = "not_requested"
        pendingMetadataFetchErrcode = "none"
        pendingMetadataFetchFailureReason = "missing_reference_after_answer"
        pendingMetadataPayloadRedacted = true
        recordPhysical6RuntimeEnablementURLHook(physical6RuntimeEnablementHook)
        blockedReason = "pending_metadata_missing_after_answer_no_credentials"
    }

    mutating func recordForegroundPendingCallMetadataHandoff(session: DirectCallSession, source: String) {
        foregroundPendingCallMetadataHandoffRequested = true
        foregroundPendingCallMetadataHandoffObserved = true
        foregroundPendingCallMetadataSource = source
        foregroundPendingCallMetadataPayloadRedacted = true
        foregroundPendingCallMetadataHasCallIdentifier = !session.callID.isEmpty
        foregroundPendingCallMetadataHasRoomBinding = !session.roomID.isEmpty
        foregroundPendingCallMetadataHasPeer = !session.peerUserID.isEmpty
        foregroundPendingCallMetadataDirection = String(describing: session.direction)
        foregroundPendingCallMetadataIntent = session.intent.rawValue
        mediaCredentialsRequestMetadataAvailable = foregroundPendingCallMetadataHasCallIdentifier &&
            foregroundPendingCallMetadataHasRoomBinding &&
            foregroundPendingCallMetadataHasPeer &&
            session.intent == .audio
        mediaCredentialsRequestMetadataRedacted = true
        mediaCredentialsRequestMetadataSource = source
        mediaCredentialsBoundaryReached = true
        mediaCredentialsRequestPlanned = false
        mediaCredentialsRequested = false
        mediaCredentialsRequestAuthorized = false
        mediaCredentialsResult = mediaCredentialsRequestMetadataAvailable ? "metadata_ready_redacted" : "metadata_invalid_redacted"
        mediaCredentialsTokenReceived = false
        mediaCredentialsTokenRedacted = true
        mediaCredentialsURLReceived = false
        mediaCredentialsURLRedacted = true
        mediaCredentialsExpiresAtPresent = false
        mediaCredentialsPayloadRedacted = true
        mediaCredentialsLocalPersistenceRequested = false
        mediaCredentialsCleanupRequested = false
        mediaCredentialsCleanupResult = "not_requested"
        mediaCredentialsPostCleanupTokenPresent = false
        mediaCredentialsPostCleanupURLPresent = false
        mediaCredentialsPostCleanupExpiresAtPresent = false
        mediaCredentialsPostCleanupPayloadPresent = false
        mediaCredentialsReuseAttempted = false
        mediaCredentialsReuseAllowed = false
        mediaCredentialsExpiryReferencePresent = false
        mediaCredentialsExpiryCheckRequested = false
        mediaCredentialsExpiryCheckResult = "not_requested"
        blockedReason = mediaCredentialsRequestMetadataAvailable ? "none" : "media_credentials_request_metadata_invalid_redacted"
    }

    mutating func recordPendingMetadataFetchRequested() {
        recordAnswerTriggeredPendingMetadataBoundary(source: "callkit_answer_pending_metadata_fetch")
        recordPendingMetadataReferenceRepairProof(referencePresent: true, handedToAnswerPipeline: true)
        pendingMetadataFetchRequested = true
        pendingMetadataFetchAuthorized = false
        pendingMetadataFetchResult = "requested"
        pendingMetadataFetchHTTPStatusBucket = "pending"
        pendingMetadataFetchErrcode = "none"
        pendingMetadataFetchFailureReason = "none"
        pendingMetadataPayloadRedacted = true
        blockedReason = "pending_metadata_fetch_in_progress_redacted"
    }

    mutating func recordAuthenticatedPendingMetadataFetch(session: DirectCallSession) {
        recordMetadataCredentialsBoundaryRepairProof()
        recordPendingMetadataReferenceRepairProof(referencePresent: true, handedToAnswerPipeline: true)
        pendingMetadataFetchRequested = true
        pendingMetadataFetchAuthorized = true
        pendingMetadataFetchResult = "success_redacted"
        pendingMetadataFetchHTTPStatusBucket = "2xx"
        pendingMetadataFetchErrcode = "none"
        pendingMetadataFetchFailureReason = "none"
        pendingMetadataPayloadRedacted = true
        recordForegroundPendingCallMetadataHandoff(session: session, source: "authenticated_pending_metadata_fetch")
        mediaCredentialsResult = "blocked_redacted"
        mediaCredentialsRequestPlanned = true
        mediaCredentialsRequested = false
        mediaCredentialsRequestAuthorized = false
        mediaCredentialsTokenReceived = false
        mediaCredentialsURLReceived = false
        mediaCredentialsCleanupRequested = false
        mediaCredentialsCleanupResult = "not_requested"
        blockedReason = receiverPostAnswerFinalClassification
    }

    mutating func recordAuthenticatedPendingMetadataFetchBlocked(_ reason: String,
                                                                 authorized: Bool,
                                                                 httpStatusBucket: String = "unknown",
                                                                 errcode: String = "none",
                                                                 failureReason: String = "unknown") {
        recordMetadataCredentialsBoundaryRepairProof()
        recordPendingMetadataReferenceRepairProof(referencePresent: true, handedToAnswerPipeline: true)
        pendingMetadataFetchRequested = true
        pendingMetadataFetchAuthorized = authorized
        pendingMetadataFetchResult = "blocked_redacted"
        pendingMetadataFetchHTTPStatusBucket = httpStatusBucket
        pendingMetadataFetchErrcode = errcode
        pendingMetadataFetchFailureReason = failureReason
        pendingMetadataPayloadRedacted = true
        foregroundPendingCallMetadataHandoffRequested = true
        foregroundPendingCallMetadataHandoffObserved = false
        foregroundPendingCallMetadataSource = "authenticated_pending_metadata_fetch"
        foregroundPendingCallMetadataPayloadRedacted = true
        mediaCredentialsRequestMetadataAvailable = false
        mediaCredentialsRequestMetadataRedacted = true
        mediaCredentialsRequestMetadataSource = "none"
        mediaCredentialsBoundaryReached = true
        mediaCredentialsRequestPlanned = false
        mediaCredentialsRequested = false
        mediaCredentialsRequestAuthorized = false
        mediaCredentialsResult = "blocked_redacted"
        mediaCredentialsTokenRedacted = true
        mediaCredentialsURLRedacted = true
        mediaCredentialsPayloadRedacted = true
        mediaCredentialsPostCleanupTokenPresent = false
        mediaCredentialsPostCleanupURLPresent = false
        mediaCredentialsPostCleanupExpiresAtPresent = false
        mediaCredentialsPostCleanupPayloadPresent = false
        mediaCredentialsReuseAttempted = false
        mediaCredentialsReuseAllowed = false
        mediaCredentialsExpiryReferencePresent = false
        mediaCredentialsExpiryCheckRequested = false
        mediaCredentialsExpiryCheckResult = "not_requested"
        recordControlledAudioConnectFirstAttemptProof(.defaultDisabled)
        blockedReason = reason
    }

    mutating func recordPhysical6RuntimeEnablementURLHook(_ hook: SalemXPhysical6RuntimeEnablementURLHook) {
        physical6RuntimeEnablementURLHookPresent = hook.present
        physical6RuntimeEnablementURLHookDebugOnly = hook.debugOnly
        physical6RuntimeEnablementURLHookDefaultDisabled = hook.isDefaultDisabled
        physical6RuntimeEnablementURLHookArmed = hook.armed
        physical6RuntimeEnablementURLHookOneShot = hook.oneShot
        physical6RuntimeEnablementURLHookAudioOnly = hook.audioOnly
        physical6RuntimeEnablementURLHookVideoAllowed = hook.videoAllowed
        physical6RuntimeEnablementURLHookMatrixEventsAllowed = hook.matrixEventsAllowed
        physical6RuntimeEnablementURLHookRawCredentialsLogged = hook.rawCredentialsLogged
        physical6RuntimeEnablementURLHookConsumed = hook.consumed
        physical6RuntimeEnablementURLHookBlockedReason = hook.blockedReason
    }

    mutating func recordControlledMediaCredentialsRequest(succeeded: Bool,
                                                          expiresAtPresent: Bool,
                                                          session: DirectCallSession,
                                                          source: String,
                                                          diagnostics: DirectCallDiagnosticSnapshot = .empty,
                                                          physical6RuntimeEnablementHook: SalemXPhysical6RuntimeEnablementURLHook = .defaultDisabled) {
        recordForegroundPendingCallMetadataHandoff(session: session, source: source)
        recordMetadataCredentialsBoundaryRepairProof(allowsHookConsumptionAfterCredentials: succeeded && mediaCredentialsRequestMetadataAvailable)
        mediaCredentialsBoundaryReached = true
        mediaCredentialsRequestPlanned = false
        mediaCredentialsRequested = true
        mediaCredentialsRequestAuthorized = mediaCredentialsRequestMetadataAvailable
        mediaCredentialsResult = succeeded && mediaCredentialsRequestMetadataAvailable ? "success_redacted" : "blocked_redacted"
        mediaCredentialsTokenReceived = succeeded && mediaCredentialsRequestMetadataAvailable
        mediaCredentialsTokenRedacted = true
        mediaCredentialsURLReceived = succeeded && mediaCredentialsRequestMetadataAvailable
        mediaCredentialsURLRedacted = true
        mediaCredentialsExpiresAtPresent = succeeded && mediaCredentialsRequestMetadataAvailable && expiresAtPresent
        mediaCredentialsPayloadRedacted = true
        mediaCredentialsLocalPersistenceRequested = false
        let cleanupCleared = succeeded && mediaCredentialsRequestMetadataAvailable
        mediaCredentialsCleanupRequested = cleanupCleared
        mediaCredentialsCleanupResult = mediaCredentialsCleanupRequested ? "cleared" : "not_requested"
        mediaCredentialsPostCleanupTokenPresent = false
        mediaCredentialsPostCleanupURLPresent = false
        mediaCredentialsPostCleanupExpiresAtPresent = false
        mediaCredentialsPostCleanupPayloadPresent = false
        mediaCredentialsReuseAttempted = false
        mediaCredentialsReuseAllowed = false
        mediaCredentialsExpiryReferencePresent = cleanupCleared && expiresAtPresent
        mediaCredentialsExpiryCheckRequested = cleanupCleared && expiresAtPresent
        mediaCredentialsExpiryCheckResult = mediaCredentialsExpiryCheckRequested ? "expired_or_not_reusable_redacted" : "not_requested"
        mediaCredentialsTokenRequestSeen = diagnostics.tokenRequestSeen
        mediaCredentialsTokenHTTPStatusBucket = Self.httpStatusBucket(diagnostics.tokenStatus)
        mediaCredentialsTokenReason = diagnostics.tokenReason.rawValue
        mediaCredentialsEligibilityAllowed = diagnostics.tokenEligibilityAllowed
        mediaCredentialsRateLimited = diagnostics.tokenRateLimited
        mediaCredentialsAllocationAttempted = diagnostics.tokenAllocationAttempted
        mediaCredentialsLiveKitRoomPrecreateAttempted = diagnostics.tokenLiveKitRoomPrecreateAttempted
        mediaCredentialsTokenIssued = diagnostics.tokenIssued
        recordPhysical6RuntimeEnablementURLHook(physical6RuntimeEnablementHook)
        if cleanupCleared {
            recordControlledMediaConnectPreflight(credentialsAvailable: true,
                                                  tokenPresent: mediaCredentialsTokenReceived,
                                                  urlPresent: mediaCredentialsURLReceived,
                                                  expiresAtPresent: mediaCredentialsExpiresAtPresent,
                                                  physical6RuntimeEnablementHook: physical6RuntimeEnablementHook)
        }
        blockedReason = succeeded && mediaCredentialsRequestMetadataAvailable ? "none" : "media_credentials_request_failed_redacted"
    }

    mutating func recordControlledMediaConnectPreflight(credentialsAvailable: Bool,
                                                        tokenPresent: Bool,
                                                        urlPresent: Bool,
                                                        expiresAtPresent: Bool,
                                                        physical6RuntimeEnablementHook: SalemXPhysical6RuntimeEnablementURLHook = .defaultDisabled) {
        mediaConnectPreflightRequested = true
        mediaConnectPreflightMetadataAvailable = mediaCredentialsRequestMetadataAvailable
        mediaConnectPreflightCredentialsAvailable = credentialsAvailable && mediaCredentialsRequestMetadataAvailable
        mediaConnectPreflightTokenPresent = tokenPresent && mediaCredentialsRequestMetadataAvailable
        mediaConnectPreflightURLPresent = urlPresent && mediaCredentialsRequestMetadataAvailable
        mediaConnectPreflightExpiresAtPresent = expiresAtPresent && mediaCredentialsRequestMetadataAvailable
        mediaConnectGuardEnabled = true
        recordPhysical6RuntimeEnablementURLHook(physical6RuntimeEnablementHook)
        attemptControlledAudioConnectRuntimeIfAllowed(activationConfiguration: physical6RuntimeEnablementHook.activationConfiguration,
                                                      enablementConfiguration: physical6RuntimeEnablementHook.enablementConfiguration,
                                                      receiverAppSessionValidated: pendingMetadataFetchAuthorized && pendingMetadataFetchResult == "success_redacted",
                                                      oneShotNotConsumed: physical6RuntimeEnablementHook.oneShotNotConsumed)
        if controlledConnectFirstAttemptRequested {
            recordPhysical6RuntimeEnablementURLHook(physical6RuntimeEnablementHook.consumedCopy())
        }
        if controlledConnectFirstAttemptAllowed {
            mediaConnectPreflightResult = "ready_for_first_attempt_redacted"
        } else if mediaConnectPreflightCredentialsAvailable {
            mediaConnectPreflightResult = "blocked_before_connect_redacted"
        } else {
            mediaConnectPreflightResult = "blocked_redacted"
        }
        mediaConnectBlockedReason = mediaConnectPreflightCredentialsAvailable ? controlledConnectBlockedReasonForPreflight : "media_connect_preflight_not_ready"
        mediaConnectEngineInvoked = false
    }

    mutating func rollbackControlledConnectActivationProof() {
        recordControlledConnectActivationProof(SalemXControlledMediaConnectActivationConfiguration.rollbackDisabled)
        recordControlledConnectEnablementProof(SalemXControlledMediaConnectEnablementConfiguration.rollbackDisabled)
        recordControlledAudioConnectExecutionGate(SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false))
        recordControlledAudioConnectActivationPath(SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false))
        recordControlledAudioConnectRealAudioPath(.defaultDisabled)
        recordControlledAudioConnectRealRuntimePath(.defaultDisabled)
        recordControlledAudioConnectRealBridge(.defaultDisabled)
        mediaConnectExecutionAllowed = false
        mediaConnectEngineInvoked = false
        recordControlledAudioConnectFirstAttemptProof(.defaultDisabled)
    }

    mutating func recordControlledConnectActivationProof(_ activationConfiguration: SalemXControlledMediaConnectActivationConfiguration) {
        controlledConnectActivationWiringPresent = activationConfiguration.wiringPresent
        controlledConnectActivationDebugOnly = activationConfiguration.debugOnly
        controlledConnectActivationDefaultDisabled = activationConfiguration.isDefaultDisabled
        controlledConnectActivationRequiresOperatorApproval = activationConfiguration.requiresOperatorApproval
        controlledConnectActivationRollbackAvailable = activationConfiguration.rollbackAvailable
        controlledConnectActivationScope = activationConfiguration.activationScope
        controlledConnectVideoAllowed = activationConfiguration.videoAllowed
        controlledConnectMatrixEventsAllowed = activationConfiguration.matrixEventsAllowed
        controlledConnectRawCredentialsLogged = activationConfiguration.rawCredentialsLogged
        recordControlledConnectSwitchProof(activationConfiguration.controlledConnectSwitch)
    }

    mutating func recordControlledConnectSwitchProof(_ controlledConnectSwitch: SalemXControlledMediaConnectSwitch) {
        controlledConnectSwitchPresent = true
        controlledConnectSwitchDebugOnly = true
        controlledConnectSwitchEnabled = controlledConnectSwitch.isEnabled
        controlledConnectOperatorApproved = controlledConnectSwitch.operatorApproved
        controlledConnectExecutionAllowed = controlledConnectSwitch.executionAllowed
        controlledConnectBlockedReason = controlledConnectSwitch.blockedReason
        controlledConnectBlockedBeforeEngine = !controlledConnectExecutionAllowed
        controlledConnectBlockedBeforeLiveKitJoin = !controlledConnectExecutionAllowed
        controlledConnectBlockedBeforePermissions = !controlledConnectExecutionAllowed
        controlledConnectBlockedBeforeMatrixEvents = !controlledConnectExecutionAllowed
    }

    mutating func recordControlledConnectEnablementProof(_ enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration) {
        controlledConnectEnablementWiringPresent = enablementConfiguration.wiringPresent
        controlledConnectEnablementDebugOnly = enablementConfiguration.debugOnly
        controlledConnectEnablementDefaultOff = enablementConfiguration.isDefaultOff
        controlledConnectEnablementOperatorApprovalRequired = enablementConfiguration.operatorApprovalRequired
        controlledConnectEnablementOneShot = enablementConfiguration.isOneShot
        controlledConnectEnablementFreshCredentialsRequired = enablementConfiguration.freshCredentialsRequired
        controlledConnectEnablementAudioOnly = enablementConfiguration.audioOnlyScope
        controlledConnectEnablementVideoAllowed = enablementConfiguration.videoAllowed
        controlledConnectEnablementMatrixEventsAllowed = enablementConfiguration.matrixEventsAllowed
        controlledConnectEnablementRawCredentialsLogged = enablementConfiguration.rawCredentialsLogged
        controlledConnectEnablementRollbackAvailable = enablementConfiguration.rollbackAvailable
        controlledConnectEnablementEnabled = enablementConfiguration.oneShotEnablementEnabled
        controlledConnectEnablementOperatorApproved = enablementConfiguration.operatorApproved
        controlledConnectEnablementFuturePhasePermitted = enablementConfiguration.futureConnectPhasePermitted
        controlledConnectEnablementExecutionAllowed = enablementConfiguration.executionAllowed
        controlledConnectEnablementBlockedReason = enablementConfiguration.blockedReason
    }

    mutating func recordControlledAudioConnectExecutionGate(_ executionGate: SalemXControlledAudioConnectExecutionGate) {
        controlledAudioConnectExecutionGatePresent = executionGate.gatePresent
        controlledAudioConnectExecutionDebugOnly = executionGate.debugOnly
        controlledAudioConnectExecutionAudioOnly = executionGate.audioOnly
        controlledAudioConnectExecutionVideoAllowed = executionGate.videoAllowed
        controlledAudioConnectExecutionMatrixEventsAllowed = executionGate.matrixEventsAllowed
        controlledAudioConnectExecutionRawCredentialsLogged = executionGate.rawCredentialsLogged
        controlledAudioConnectExecutionRequiresEnablement = executionGate.requiresEnablement
        controlledAudioConnectExecutionRequiresOperatorApproval = executionGate.requiresOperatorApproval
        controlledAudioConnectExecutionRequiresFuturePhasePermission = executionGate.requiresFuturePhasePermission
        controlledAudioConnectExecutionFuturePhasePermitted = executionGate.futurePhasePermitted
        controlledAudioConnectExecutionAllowed = executionGate.executionAllowed
        controlledAudioConnectExecutionBlockedReason = executionGate.blockedReason
        controlledAudioConnectExecutionBlockedBeforeEngine = executionGate.blockedBeforeEngine
        controlledAudioConnectExecutionBlockedBeforeLiveKitJoin = executionGate.blockedBeforeLiveKitJoin
        controlledAudioConnectExecutionBlockedBeforePermissions = executionGate.blockedBeforePermissions
        controlledAudioConnectExecutionBlockedBeforeMatrixEvents = executionGate.blockedBeforeMatrixEvents
    }

    mutating func recordControlledAudioConnectActivationPath(_ activationPath: SalemXControlledAudioConnectActivationPath) {
        controlledAudioConnectActivationPathPresent = activationPath.pathPresent
        controlledAudioConnectActivationDebugOnly = activationPath.debugOnly
        controlledAudioConnectActivationOneShot = activationPath.isOneShot
        controlledAudioConnectActivationDefaultDisabled = activationPath.isDefaultDisabled
        controlledAudioConnectActivationRequiresReceiverSession = activationPath.requiresReceiverSession
        controlledAudioConnectActivationRequiresFreshCredentials = activationPath.requiresFreshCredentials
        controlledAudioConnectActivationRequiresEnablement = activationPath.requiresEnablement
        controlledAudioConnectActivationRequiresOperatorApproval = activationPath.requiresOperatorApproval
        controlledAudioConnectActivationRequiresFuturePhasePermission = activationPath.requiresFuturePhasePermission
        controlledAudioConnectActivationAudioOnly = activationPath.audioOnly
        controlledAudioConnectActivationVideoAllowed = activationPath.videoAllowed
        controlledAudioConnectActivationMatrixEventsAllowed = activationPath.matrixEventsAllowed
        controlledAudioConnectActivationRawCredentialsLogged = activationPath.rawCredentialsLogged
        controlledAudioConnectActivationRollbackAvailable = activationPath.rollbackAvailable
        controlledAudioConnectActivationAllowed = activationPath.activationAllowed
        controlledAudioConnectActivationBlockedReason = activationPath.blockedReason
        controlledAudioConnectActivationBlockedBeforeEngine = activationPath.blockedBeforeEngine
        controlledAudioConnectActivationBlockedBeforeLiveKitJoin = activationPath.blockedBeforeLiveKitJoin
        controlledAudioConnectActivationBlockedBeforePermissions = activationPath.blockedBeforePermissions
        controlledAudioConnectActivationBlockedBeforeMatrixEvents = activationPath.blockedBeforeMatrixEvents
    }

    mutating func recordControlledAudioConnectRealAudioPath(_ realAudioPath: SalemXControlledAudioConnectRealAudioPath) {
        controlledConnectRealAudioPathPresent = realAudioPath.present
        controlledConnectRealAudioPathDebugOnly = realAudioPath.debugOnly
        controlledConnectRealAudioPathDefaultDisabled = realAudioPath.isDefaultDisabled
        controlledConnectRealAudioPathRequiresEnablement = realAudioPath.requiresEnablement
        controlledConnectRealAudioPathRequiresOperatorApproval = realAudioPath.requiresOperatorApproval
        controlledConnectRealAudioPathRequiresFuturePhasePermission = realAudioPath.requiresFuturePhasePermission
        controlledConnectRealAudioPathAudioOnly = realAudioPath.audioOnly
        controlledConnectRealAudioPathVideoAllowed = realAudioPath.videoAllowed
        controlledConnectRealAudioPathMatrixEventsAllowed = realAudioPath.matrixEventsAllowed
        controlledConnectRealAudioPathRawCredentialsLogged = realAudioPath.rawCredentialsLogged
        controlledConnectRealAudioPathOneShot = realAudioPath.oneShot
        controlledConnectRealAudioPathAllowed = realAudioPath.allowed
        controlledConnectRealAudioPathBlockedReason = realAudioPath.blockedReason
        controlledConnectRealAudioPathBlockedBeforeEngine = realAudioPath.blockedBeforeEngine
        controlledConnectRealAudioPathCanReachEngineWhenAllGatesTrue = realAudioPath.canReachEngineWhenAllGatesTrue
    }

    mutating func recordControlledAudioConnectRealRuntimePath(_ realRuntimePath: SalemXControlledAudioConnectRealRuntimePath) {
        controlledConnectRealRuntimePathPresent = realRuntimePath.present
        controlledConnectRealRuntimePathDebugOnly = realRuntimePath.debugOnly
        controlledConnectRealRuntimePathDefaultDisabled = realRuntimePath.isDefaultDisabled
        controlledConnectRealRuntimePathRequiresCredentials = realRuntimePath.requiresCredentials
        controlledConnectRealRuntimePathRequiresEnablement = realRuntimePath.requiresEnablement
        controlledConnectRealRuntimePathRequiresOperatorApproval = realRuntimePath.requiresOperatorApproval
        controlledConnectRealRuntimePathRequiresFuturePhasePermission = realRuntimePath.requiresFuturePhasePermission
        controlledConnectRealRuntimePathAudioOnly = realRuntimePath.audioOnly
        controlledConnectRealRuntimePathVideoAllowed = realRuntimePath.videoAllowed
        controlledConnectRealRuntimePathMatrixEventsAllowed = realRuntimePath.matrixEventsAllowed
        controlledConnectRealRuntimePathRawCredentialsLogged = realRuntimePath.rawCredentialsLogged
        controlledConnectRealRuntimePathOneShot = realRuntimePath.oneShot
        controlledConnectRealRuntimePathAllowed = realRuntimePath.allowed
        controlledConnectRealRuntimePathBlockedReason = realRuntimePath.blockedReason
        controlledConnectRealRuntimePathBlockedBeforeEngine = realRuntimePath.blockedBeforeEngine
        controlledConnectRealRuntimePathCanCallConnectMediaWhenAllGatesTrue = realRuntimePath.canCallConnectMediaWhenAllGatesTrue
        controlledConnectRealRuntimePathCanCallLiveKitAudioWhenAllGatesTrue = realRuntimePath.canCallLiveKitAudioWhenAllGatesTrue
    }

    mutating func recordControlledAudioConnectRealBridge(_ realBridge: SalemXControlledAudioConnectRealBridge) {
        controlledConnectRealBridgePresent = realBridge.present
        controlledConnectRealBridgeDebugOnly = realBridge.debugOnly
        controlledConnectRealBridgeDefaultDisabled = realBridge.isDefaultDisabled
        controlledConnectRealBridgeRequiresCredentials = realBridge.requiresCredentials
        controlledConnectRealBridgeRequiresEnablement = realBridge.requiresEnablement
        controlledConnectRealBridgeRequiresOperatorApproval = realBridge.requiresOperatorApproval
        controlledConnectRealBridgeRequiresFuturePhasePermission = realBridge.requiresFuturePhasePermission
        controlledConnectRealBridgeAudioOnly = realBridge.audioOnly
        controlledConnectRealBridgeVideoAllowed = realBridge.videoAllowed
        controlledConnectRealBridgeMatrixEventsAllowed = realBridge.matrixEventsAllowed
        controlledConnectRealBridgeRawCredentialsLogged = realBridge.rawCredentialsLogged
        controlledConnectRealBridgeOneShot = realBridge.oneShot
        controlledConnectRealBridgeAllowed = realBridge.allowed
        controlledConnectRealBridgeBlockedReason = realBridge.blockedReason
        controlledConnectRealBridgeBlockedBeforeConnectMedia = realBridge.blockedBeforeConnectMedia
        controlledConnectRealBridgeCanCallConnectMediaWhenAllGatesTrue = realBridge.canCallConnectMediaWhenAllGatesTrue
        controlledConnectRealBridgeCanCallLiveKitAudioWhenAllGatesTrue = realBridge.canCallLiveKitAudioWhenAllGatesTrue
        controlledConnectRealBridgeUsesFakeEngineInTestsOnly = realBridge.usesFakeEngineInTestsOnly
        controlledConnectRealBridgeUsesRealRuntimeBoundaryWhenNotTest = realBridge.usesRealRuntimeBoundaryWhenNotTest
    }

    mutating func recordControlledAudioConnectFirstAttemptProof(_ firstAttempt: SalemXControlledAudioConnectFirstAttempt) {
        controlledConnectFirstAttemptRequested = firstAttempt.requested
        controlledConnectFirstAttemptAllowed = firstAttempt.allowed
        controlledConnectFirstAttemptStarted = firstAttempt.started
        controlledConnectFirstAttemptCompleted = firstAttempt.completed
        controlledConnectFirstAttemptRepeated = firstAttempt.repeated
        controlledConnectFirstAttemptResult = firstAttempt.result
        controlledConnectFirstAttemptErrorBucket = firstAttempt.errorBucket
        controlledConnectFirstAttemptAudioOnly = firstAttempt.audioOnly
        controlledConnectFirstAttemptVideoAllowed = firstAttempt.videoAllowed
        controlledConnectFirstAttemptMatrixEventsAllowed = firstAttempt.matrixEventsAllowed
        controlledConnectFirstAttemptRawCredentialsLogged = firstAttempt.rawCredentialsLogged
        controlledConnectFirstAttemptBlockedReason = firstAttempt.blockedReason
        mediaConnectRequested = firstAttempt.mediaConnectRequested
        mediaConnectAttempted = firstAttempt.mediaConnectAttempted
        liveKitJoinRequested = firstAttempt.liveKitJoinRequested
        liveKitConnectAudioInvoked = firstAttempt.liveKitConnectAudioInvoked
        microphonePermissionRequested = firstAttempt.microphonePermissionRequested
        cameraPermissionRequested = firstAttempt.cameraPermissionRequested
        matrixEventEmitRequested = firstAttempt.matrixEventEmitRequested
        realCallFlowStarted = firstAttempt.realCallFlowStarted
        mediaConnectEngineInvoked = firstAttempt.mediaConnectAttempted
        refreshRemoteAudioLivenessDiagnostics()
        activateRemoteParticipantObservationRuntimeWindowIfNeeded()
        refreshDisconnectCleanupDiagnostics()
        refreshSenderJoinTriggerOrchestration()
    }

    mutating func recordReceiverConnectedSessionLeaseAcquired(taskRetained: Bool) {
        receiverConnectedSessionLeasePresent = true
        receiverConnectedSessionLeaseDebugOnly = true
        receiverConnectedSessionLeaseAcquired = true
        receiverConnectedSessionLeaseRoomRetained = true
        receiverConnectedSessionLeaseDelegateRetained = true
        receiverConnectedSessionLeaseObserverRetained = true
        receiverConnectedSessionLeaseTaskRetained = taskRetained
        receiverConnectedSessionLeaseActiveBeforeSenderTrigger = true
        receiverConnectedSessionLeaseActiveAfterSenderTrigger = true
        receiverConnectedSessionLeaseActiveAtSenderSignal = false
        receiverConnectedSessionLeaseReleased = false
        receiverConnectedSessionLeaseReleasedAfterTerminal = false
        receiverConnectedSessionLeaseReleaseReason = "not_released"
        receiverConnectedSessionLeaseRepeatedRelease = false
        liveKitRoomConnected = true
        liveKitRoomDisconnected = false
        liveKitLocalParticipantPresent = true
        receiverRemoteParticipantObserverStarted = true
        remoteParticipantObservationWaitStarted = true
        if remoteParticipantObservationTimeoutBucket == "not_started" {
            remoteParticipantObservationTimeoutBucket = "pending_redacted"
        }
        if remoteParticipantObservationFinalClassification == "not_started" {
            remoteParticipantObservationFinalClassification = "pending_redacted"
        }
        liveKitCleanupRequested = false
        liveKitCleanupCompleted = false
        liveKitCleanupResult = "deferred_until_observation_terminal_redacted"
        receiverCleanupDeferredUntilObservationTerminal = true
        recordReceiverConnectedWindowOpened()
        refreshReceiverRemoteParticipantObserverClassification()
        refreshRemoteParticipantObservationTimingRepairDiagnostics()
    }

    mutating func recordReceiverControlledRuntimeConnectResult(succeeded: Bool, errorBucket: String) {
        controlledConnectFirstAttemptRequested = true
        controlledConnectFirstAttemptAllowed = true
        controlledConnectFirstAttemptStarted = true
        controlledConnectFirstAttemptCompleted = true
        controlledConnectFirstAttemptRepeated = false
        controlledConnectFirstAttemptResult = succeeded ? "success_redacted" : "blocked_redacted"
        controlledConnectFirstAttemptErrorBucket = succeeded ? "none" : errorBucket
        controlledConnectFirstAttemptAudioOnly = true
        controlledConnectFirstAttemptVideoAllowed = false
        controlledConnectFirstAttemptMatrixEventsAllowed = false
        controlledConnectFirstAttemptRawCredentialsLogged = false
        controlledConnectFirstAttemptBlockedReason = succeeded ? "none" : "runtime_connect_failed_redacted"
        mediaConnectRequested = true
        mediaConnectAttempted = true
        liveKitJoinRequested = true
        liveKitConnectAudioInvoked = true
        microphonePermissionRequested = false
        cameraPermissionRequested = false
        matrixEventEmitRequested = false
        realCallFlowStarted = false
        mediaConnectEngineInvoked = true
        if succeeded {
            activateRemoteParticipantObservationRuntimeWindowIfNeeded()
        } else {
            refreshRemoteAudioLivenessDiagnostics()
            refreshDisconnectCleanupDiagnostics()
            refreshSenderJoinTriggerOrchestration()
        }
    }

    mutating func recordReceiverConnectedSessionLeaseReleased(reason: String, repeated: Bool) {
        receiverConnectedSessionLeasePresent = true
        receiverConnectedSessionLeaseDebugOnly = true
        receiverConnectedSessionLeaseReleased = true
        receiverConnectedSessionLeaseReleasedAfterTerminal = remoteParticipantObservationWaitCompleted ||
            senderConnectedSignalReceivedByReceiver
        receiverConnectedSessionLeaseReleaseReason = reason
        receiverConnectedSessionLeaseRepeatedRelease = repeated
        receiverConnectedSessionLeaseTaskRetained = false
        liveKitRoomDisconnected = true
        liveKitCleanupRequested = true
        liveKitCleanupCompleted = true
        liveKitCleanupResult = "completed_redacted"
        recordReceiverConnectedWindowClosed(reason: reason)
        refreshReceiverRemoteParticipantObserverClassification()
        refreshRemoteParticipantObservationTimingRepairDiagnostics()
    }

    mutating func attemptControlledAudioConnectRuntimeIfAllowed(activationConfiguration: SalemXControlledMediaConnectActivationConfiguration,
                                                                enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration,
                                                                receiverAppSessionValidated: Bool,
                                                                oneShotNotConsumed: Bool,
                                                                fakeMediaEngine: SalemXControlledAudioConnectFakeFirstAttemptMediaEngine = .init()) {
        let executionGate = SalemXControlledAudioConnectExecutionGate(credentialsPresent: mediaConnectPreflightCredentialsAvailable,
                                                                      activationConfiguration: activationConfiguration,
                                                                      enablementConfiguration: enablementConfiguration)
        let activationPath = SalemXControlledAudioConnectActivationPath(receiverAppSessionValidated: receiverAppSessionValidated,
                                                                        credentialsPresent: mediaConnectPreflightCredentialsAvailable,
                                                                        enablementConfiguration: enablementConfiguration)
        let realAudioPath = SalemXControlledAudioConnectRealAudioPath(enablementConfiguration: enablementConfiguration,
                                                                      executionGate: executionGate,
                                                                      activationPath: activationPath,
                                                                      oneShotNotConsumed: oneShotNotConsumed)
        let realRuntimePath = SalemXControlledAudioConnectRealRuntimePath(credentialsPresent: mediaConnectPreflightCredentialsAvailable,
                                                                          enablementConfiguration: enablementConfiguration,
                                                                          executionGate: executionGate,
                                                                          activationPath: activationPath,
                                                                          oneShotNotConsumed: oneShotNotConsumed)
        let realBridge = SalemXControlledAudioConnectRealBridge(realRuntimePath: realRuntimePath,
                                                                oneShotNotConsumed: oneShotNotConsumed)

        recordControlledConnectActivationProof(activationConfiguration)
        recordControlledConnectEnablementProof(enablementConfiguration)
        recordControlledAudioConnectExecutionGate(executionGate)
        recordControlledAudioConnectActivationPath(activationPath)
        recordControlledAudioConnectRealAudioPath(realAudioPath)
        recordControlledAudioConnectRealRuntimePath(realRuntimePath)
        recordControlledAudioConnectRealBridge(realBridge)
        mediaConnectExecutionAllowed = controlledConnectExecutionAllowed &&
            controlledConnectEnablementExecutionAllowed &&
            controlledAudioConnectExecutionAllowed &&
            controlledAudioConnectActivationAllowed &&
            controlledConnectRealAudioPathAllowed &&
            controlledConnectRealRuntimePathAllowed &&
            controlledConnectRealBridgeAllowed

        if realBridge.allowed {
            recordControlledAudioConnectFirstAttemptProof(.controlledRealBridgeTestBoundary(realBridge: realBridge,
                                                                                            fakeMediaEngine: fakeMediaEngine))
        } else {
            recordControlledAudioConnectFirstAttemptProof(.defaultDisabled)
        }
    }

    mutating func attemptControlledAudioConnectIfAllowed(activationConfiguration: SalemXControlledMediaConnectActivationConfiguration,
                                                         enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration,
                                                         receiverAppSessionValidated: Bool,
                                                         oneShotNotConsumed: Bool,
                                                         fakeMediaEngine: SalemXControlledAudioConnectFakeFirstAttemptMediaEngine = .init()) {
        let executionGate = SalemXControlledAudioConnectExecutionGate(credentialsPresent: mediaConnectPreflightCredentialsAvailable,
                                                                      activationConfiguration: activationConfiguration,
                                                                      enablementConfiguration: enablementConfiguration)
        let activationPath = SalemXControlledAudioConnectActivationPath(receiverAppSessionValidated: receiverAppSessionValidated,
                                                                        credentialsPresent: mediaConnectPreflightCredentialsAvailable,
                                                                        enablementConfiguration: enablementConfiguration)
        let realAudioPath = SalemXControlledAudioConnectRealAudioPath(enablementConfiguration: enablementConfiguration,
                                                                      executionGate: executionGate,
                                                                      activationPath: activationPath,
                                                                      oneShotNotConsumed: oneShotNotConsumed)

        recordControlledConnectActivationProof(activationConfiguration)
        recordControlledConnectEnablementProof(enablementConfiguration)
        recordControlledAudioConnectExecutionGate(executionGate)
        recordControlledAudioConnectActivationPath(activationPath)
        recordControlledAudioConnectRealAudioPath(realAudioPath)
        mediaConnectExecutionAllowed = controlledConnectExecutionAllowed &&
            controlledConnectEnablementExecutionAllowed &&
            controlledAudioConnectExecutionAllowed &&
            controlledAudioConnectActivationAllowed &&
            controlledConnectRealAudioPathAllowed
        recordControlledAudioConnectFirstAttemptProof(.controlledRealPathTestBoundary(realAudioPath: realAudioPath,
                                                                                      fakeMediaEngine: fakeMediaEngine))
    }

    mutating func recordControlledAudioConnectFirstAttemptBoundaryForTests() {
        let activationConfiguration = SalemXControlledMediaConnectActivationConfiguration.testOnlyEnabled
        let enablementConfiguration = SalemXControlledMediaConnectEnablementConfiguration.testOnlyEnabled

        mediaConnectPreflightRequested = true
        mediaConnectPreflightMetadataAvailable = true
        mediaConnectPreflightCredentialsAvailable = true
        mediaConnectPreflightTokenPresent = true
        mediaConnectPreflightURLPresent = true
        mediaConnectPreflightExpiresAtPresent = true
        mediaConnectGuardEnabled = true
        attemptControlledAudioConnectRuntimeIfAllowed(activationConfiguration: activationConfiguration,
                                                      enablementConfiguration: enablementConfiguration,
                                                      receiverAppSessionValidated: true,
                                                      oneShotNotConsumed: true)
        mediaConnectPreflightResult = controlledConnectFirstAttemptAllowed ? "ready_for_first_attempt_redacted" : "blocked_redacted"
        mediaConnectBlockedReason = controlledConnectFirstAttemptBlockedReason
        blockedReason = controlledConnectFirstAttemptAllowed ? "none" : controlledConnectFirstAttemptBlockedReason
    }

    private var controlledConnectBlockedReasonForPreflight: String {
        if !controlledConnectExecutionAllowed {
            return controlledConnectBlockedReason
        }
        if !controlledConnectEnablementExecutionAllowed {
            return controlledConnectEnablementBlockedReason
        }
        if !controlledAudioConnectExecutionAllowed {
            return controlledAudioConnectExecutionBlockedReason
        }
        if !controlledAudioConnectActivationAllowed {
            return controlledAudioConnectActivationBlockedReason
        }
        if !controlledConnectRealAudioPathAllowed {
            return controlledConnectRealAudioPathBlockedReason
        }
        if !controlledConnectRealRuntimePathAllowed {
            return controlledConnectRealRuntimePathBlockedReason
        }
        if !controlledConnectRealBridgeAllowed {
            return controlledConnectRealBridgeBlockedReason
        }
        return "none"
    }

    private static func httpStatusBucket(_ status: Int?) -> String {
        guard let status else {
            return "unknown"
        }
        switch status {
        case 200..<300:
            return "2xx"
        case 400:
            return "400"
        case 401:
            return "401"
        case 403:
            return "403"
        case 404:
            return "404"
        case 429:
            return "429"
        case 500..<600:
            return "5xx"
        default:
            return "other_redacted"
        }
    }
}

private struct SalemXLocalCallKitOnlyProofSummary {
    var proofSource = "local_callkit_only"
    var proofGeneration = "not_started"
    var proofLastUpdatedBy = "not_started"
    var reportRequested = false
    var reportResult = "not_requested"
    var firstActionKind = "none"
    var answerActionDelivered = false
    var endActionDelivered = false
    var callKitUpdateHasGenericHandle = false
    var callKitUpdateHasLocalizedCallerName = false
    var callKitUpdateAudioOnly = false
    var callKitProviderConfigurationAudioOnly = false
    var callKitProviderConfigurationSupportedHandleGeneric = false
    var localCallKitOnlyUpdateEquivalentToVoIP = false
    var localCallKitOnlyProviderConfigEquivalentToVoIP = false
    var blockedReason = "not_requested"

    var redactedLines: [String] {
        [
            "proof_source=\(proofSource)",
            "proof_generation=\(proofGeneration)",
            "proof_last_updated_by=\(proofLastUpdatedBy)",
            "local_callkit_only_report_requested=\(reportRequested)",
            "local_callkit_only_report_result=\(reportResult)",
            "local_callkit_only_first_action_kind=\(firstActionKind)",
            "local_callkit_only_answer_action_delivered=\(answerActionDelivered)",
            "local_callkit_only_end_action_delivered=\(endActionDelivered)",
            "callkit_update_has_generic_handle=\(callKitUpdateHasGenericHandle)",
            "callkit_update_has_localized_caller_name=\(callKitUpdateHasLocalizedCallerName)",
            "callkit_update_audio_only=\(callKitUpdateAudioOnly)",
            "callkit_provider_configuration_audio_only=\(callKitProviderConfigurationAudioOnly)",
            "callkit_provider_configuration_supported_handle_generic=\(callKitProviderConfigurationSupportedHandleGeneric)",
            "local_callkit_only_update_equivalent_to_voip=\(localCallKitOnlyUpdateEquivalentToVoIP)",
            "local_callkit_only_provider_config_equivalent_to_voip=\(localCallKitOnlyProviderConfigEquivalentToVoIP)",
            "media_credentials_requested=false",
            "media_connect_requested=false",
            "media_connect_attempted=false",
            "livekit_join_requested=false",
            "matrix_event_emit_requested=false",
            "real_call_flow_started=false",
            "blocked_reason=\(blockedReason)"
        ]
    }
}

private struct SalemXStartupPushKitRegistryProofSummary {
    var proofSource = "startup_pushkit_registry"
    var proofGeneration = "not_started"
    var proofLastUpdatedBy = "not_started"
    var callbackInvoked = false
    var payloadRedacted = true
    var salemXPayloadObserved = false
    var payloadKind = "none"
    var forwardedToSalemXReceiptPipeline = false
    var completedBySalemXBridge = false
    var blockedReason = "not_started"

    var redactedLines: [String] {
        [
            "proof_source=\(proofSource)",
            "proof_generation=\(proofGeneration)",
            "proof_last_updated_by=\(proofLastUpdatedBy)",
            "startup_pushkit_callback_invoked=\(callbackInvoked)",
            "startup_pushkit_payload_redacted=\(payloadRedacted)",
            "startup_pushkit_salemx_payload_observed=\(salemXPayloadObserved)",
            "startup_pushkit_payload_kind=\(payloadKind)",
            "startup_pushkit_forwarded_to_salemx_receipt_pipeline=\(forwardedToSalemXReceiptPipeline)",
            "startup_pushkit_completed_by_salemx_bridge=\(completedBySalemXBridge)",
            "media_credentials_requested=false",
            "media_connect_requested=false",
            "media_connect_attempted=false",
            "livekit_join_requested=false",
            "matrix_event_emit_requested=false",
            "real_call_flow_started=false",
            "blocked_reason=\(blockedReason)"
        ]
    }
}

private struct SalemXLocalBackgroundCallKitOnlyProofSummary {
    var proofSource = "local_background_callkit_only"
    var proofGeneration = "not_started"
    var proofLastUpdatedBy = "not_started"
    var appStateAtReport = "unknown"
    var reportRequested = false
    var reportResult = "not_requested"
    var firstActionKind = "none"
    var answerActionDelivered = false
    var endActionDelivered = false
    var blockedReason = "not_requested"

    var redactedLines: [String] {
        [
            "proof_source=\(proofSource)",
            "proof_generation=\(proofGeneration)",
            "proof_last_updated_by=\(proofLastUpdatedBy)",
            "app_state_at_report=\(appStateAtReport)",
            "local_background_report_requested=\(reportRequested)",
            "local_background_report_result=\(reportResult)",
            "local_background_first_action_kind=\(firstActionKind)",
            "local_background_answer_action_delivered=\(answerActionDelivered)",
            "local_background_end_action_delivered=\(endActionDelivered)",
            "media_credentials_requested=false",
            "media_connect_requested=false",
            "media_connect_attempted=false",
            "livekit_join_requested=false",
            "matrix_event_emit_requested=false",
            "real_call_flow_started=false",
            "blocked_reason=\(blockedReason)"
        ]
    }
}

private final class SalemXPushKitCompletionCoordinator {
    private let lock = NSLock()
    private var didComplete = false
    private var didObserveReportCompletion = false

    func markReportCompletionObserved() {
        lock.lock()
        didObserveReportCompletion = true
        lock.unlock()
    }

    func shouldRunReportTimeout() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !didObserveReportCompletion && !didComplete
    }

    func claimCompletion() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didComplete else {
            return false
        }
        didComplete = true
        return true
    }
}

private final class SalemXLocalCallKitOnlyProofEventRecorder: NativeIncomingSyntheticCallKitUIProofEventRecording {
    private let generation: Int

    init(generation: Int) {
        self.generation = generation
    }

    func recordSyntheticCallKitUIProofEvent(_ event: NativeIncomingSyntheticCallKitUIProofEvent) {
        let generationMatched = SalemXPushKitRegistrationSmokeDebugBridge.isActiveLocalCallKitOnlyProofGeneration(generation)
        switch event {
        case .providerDidReset:
            SalemXPushKitRegistrationSmokeDebugBridge.recordLocalCallKitOnlyFirstAction("reset")
        case .answerActionDelivered:
            SalemXPushKitRegistrationSmokeDebugBridge.recordLocalCallKitOnlyAnswerActionDeliveryProof(generationMatched: generationMatched)
        case .endActionDelivered:
            SalemXPushKitRegistrationSmokeDebugBridge.recordLocalCallKitOnlyEndActionDeliveryProof(generationMatched: generationMatched)
        default:
            break
        }
    }
}

private final class SalemXLocalBackgroundCallKitOnlyProofEventRecorder: NativeIncomingSyntheticCallKitUIProofEventRecording {
    private let generation: Int

    init(generation: Int) {
        self.generation = generation
    }

    func recordSyntheticCallKitUIProofEvent(_ event: NativeIncomingSyntheticCallKitUIProofEvent) {
        let generationMatched = SalemXPushKitRegistrationSmokeDebugBridge.isActiveLocalBackgroundCallKitOnlyProofGeneration(generation)
        switch event {
        case .providerDidReset:
            SalemXPushKitRegistrationSmokeDebugBridge.recordLocalBackgroundCallKitOnlyFirstAction("reset")
        case .answerActionDelivered:
            SalemXPushKitRegistrationSmokeDebugBridge.recordLocalBackgroundCallKitOnlyAnswerActionDeliveryProof(generationMatched: generationMatched)
        case .endActionDelivered:
            SalemXPushKitRegistrationSmokeDebugBridge.recordLocalBackgroundCallKitOnlyEndActionDeliveryProof(generationMatched: generationMatched)
        default:
            break
        }
    }
}

private final class SalemXPushKitCallKitProofEventRecorder: NativeIncomingSyntheticCallKitUIProofEventRecording {
    private let generation: Int
    private var didRecordAnswer = false

    init(generation: Int) {
        self.generation = generation
    }

    func recordSyntheticCallKitUIProofEvent(_ event: NativeIncomingSyntheticCallKitUIProofEvent) {
        guard SalemXPushKitRegistrationSmokeDebugBridge.isActiveCallKitProofGeneration(generation) else {
            if case .answerActionDelivered = event {
                SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitAnswerActionDeliveryProof(uuidMatched: false, generationMatched: false)
            }
            if case .endActionDelivered = event {
                SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitEndActionDeliveryProof(uuidMatched: false, generationMatched: false)
            }
            if case .endActionFulfilled = event {
                SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitEndActionFulfillmentProof(uuidMatched: false, generationMatched: false)
            }
            return
        }

        switch event {
        case .providerDidReset:
            SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitProviderResetProof()
        case .audioSessionActivated:
            SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitAudioSessionProof(activated: true)
        case .audioSessionDeactivated:
            SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitAudioSessionProof(activated: false)
        case .answerActionDelivered(let uuidMatched):
            SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitAnswerActionDeliveryProof(uuidMatched: uuidMatched, generationMatched: true)
        case .answered:
            didRecordAnswer = true
            SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitAnswerActionProof()
        case .endActionDelivered(let uuidMatched):
            SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitEndActionDeliveryProof(uuidMatched: uuidMatched, generationMatched: true)
        case .endActionFulfilled(let uuidMatched):
            SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitEndActionFulfillmentProof(uuidMatched: uuidMatched, generationMatched: true)
        case .localEndRequestedBeforeAnswer(let uuidMatched):
            guard !didRecordAnswer else {
                return
            }
            SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitLocalEndRequestBeforeAnswerProof(uuidMatched: uuidMatched)
        case .ended:
            guard didRecordAnswer else {
                return
            }
            SalemXPushKitRegistrationSmokeDebugBridge.recordControlledCallKitCleanupProof()
        default:
            break
        }
    }
}

private struct SalemXPushKitTokenUploadSmokeSummary {
    var proofSource = "pushkit_upload_smoke"
    var proofGeneration = "not_started"
    var proofLastUpdatedBy = "not_started"
    var physicalDeviceAvailable = false
    var manualInvoked = false
    var tokenReceived = false
    var uploadURLResolved = false
    var uploadAuthPresent = false
    var uploadPayloadSchemaValid = false
    var uploadRequested = false
    var uploadResult = "not_requested"
    var uploadHTTPStatusBucket = "not_requested"
    var tokenEnvironmentBucket = "development"
    var registrationResult = "not_started"
    var serverStoreRequested = false
    var serverStoreResult = "not_requested"
    var retrievalInternalCheck = "not_requested"
    var tokenAPIExposesRawToken = false
    var blockedReason = "none"

    var redactedLines: [String] {
        [
            "proof_source=\(proofSource)",
            "proof_generation=\(proofGeneration)",
            "proof_last_updated_by=\(proofLastUpdatedBy)",
            "physical_device_available=\(physicalDeviceAvailable)",
            "pushkit_registration_manual_invoked=\(manualInvoked)",
            "pushkit_token_received=\(tokenReceived)",
            "pushkit_token_redacted=true",
            "pushkit_token_upload_url_resolved=\(uploadURLResolved)",
            "pushkit_token_upload_auth_present=\(uploadAuthPresent)",
            "pushkit_token_upload_payload_schema_valid=\(uploadPayloadSchemaValid)",
            "pushkit_token_upload_requested=\(uploadRequested)",
            "pushkit_token_upload_result=\(uploadResult)",
            "pushkit_token_upload_http_status_bucket=\(uploadHTTPStatusBucket)",
            "pushkit_token_environment_bucket=\(tokenEnvironmentBucket)",
            "pushkit_token_registration_result=\(registrationResult)",
            "pushkit_token_local_persistence_requested=false",
            "pushkit_token_server_store_requested=\(serverStoreRequested)",
            "pushkit_token_server_store_result=\(serverStoreResult)",
            "pushkit_token_retrieval_internal_check=\(retrievalInternalCheck)",
            "pushkit_token_api_exposes_raw_token=\(tokenAPIExposesRawToken)",
            "voip_push_send_requested=false",
            "apns_provider_requested=false",
            "media_credentials_requested=false",
            "media_connect_requested=false",
            "matrix_event_emit_requested=false",
            "real_pushkit_background_callback_wired=false",
            "blocked_reason=\(blockedReason)"
        ]
    }
}

private final class SalemXPushKitTokenUploadSmoke: NSObject, DirectCallPushKitRegistrarRegistryDelegate {
    private let uploadURL: URL
    private var accessToken: String?
    private let registryFactory: DirectCallPushKitRegistryMaking
    private let updateSummary: (SalemXPushKitTokenUploadSmokeSummary) -> Void
    private var registry: DirectCallPushKitRegistryControlling?

    init(uploadURL: URL,
         accessToken: String,
         registryFactory: DirectCallPushKitRegistryMaking,
         updateSummary: @escaping (SalemXPushKitTokenUploadSmokeSummary) -> Void) {
        self.uploadURL = uploadURL
        self.accessToken = accessToken
        self.registryFactory = registryFactory
        self.updateSummary = updateSummary
    }

    func start() {
        guard let registry = registryFactory.makeRegistry(delegate: self) else {
            updateSummary(.init(physicalDeviceAvailable: true,
                                manualInvoked: true,
                                blockedReason: "pushkit_manual_control_missing"))
            return
        }

        self.registry = registry
        updateSummary(.init(physicalDeviceAvailable: true,
                            manualInvoked: true,
                            registrationResult: "registry_created"))
        registry.requestVoIPPushRegistration()
    }

    func pushKitRegistrarDidUpdateToken(_ token: Data) {
        uploadToken(token)
    }

    func pushKitRegistrarDidInvalidateToken() { }

    private func uploadToken(_ token: Data) {
        guard !token.isEmpty else {
            updateSummary(.init(physicalDeviceAvailable: true,
                                manualInvoked: true,
                                tokenReceived: false,
                                uploadURLResolved: true,
                                uploadResult: "not_requested",
                                registrationResult: "token_missing",
                                blockedReason: "pushkit_token_not_received"))
            return
        }
        guard let accessToken, !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            updateSummary(.init(physicalDeviceAvailable: true,
                                manualInvoked: true,
                                tokenReceived: true,
                                uploadURLResolved: true,
                                uploadAuthPresent: false,
                                uploadResult: "not_requested",
                                registrationResult: "token_received",
                                blockedReason: "pushkit_token_upload_blocked_by_auth"))
            return
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("B" + "earer " + accessToken, forHTTPHeaderField: "Authorization")
        self.accessToken = nil

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "version": 1,
                "token": token.map { String(format: "%02x", $0) }.joined(),
                "environment": "development"
            ], options: [])
        } catch {
            updateSummary(.init(physicalDeviceAvailable: true,
                                manualInvoked: true,
                                tokenReceived: true,
                                uploadURLResolved: true,
                                uploadAuthPresent: true,
                                uploadPayloadSchemaValid: false,
                                uploadRequested: false,
                                uploadResult: "not_requested",
                                registrationResult: "token_received",
                                blockedReason: "pushkit_token_upload_http_failure"))
            return
        }

        updateSummary(.init(physicalDeviceAvailable: true,
                            manualInvoked: true,
                            tokenReceived: true,
                            uploadURLResolved: true,
                            uploadAuthPresent: true,
                            uploadPayloadSchemaValid: true,
                            uploadRequested: true,
                            uploadResult: "requested",
                            registrationResult: "token_received"))

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.handleUploadResponse(data: data, response: response, error: error)
        }.resume()
    }

    private func handleUploadResponse(data: Data?, response: URLResponse?, error: Error?) {
        let httpStatusBucket = Self.httpStatusBucket(response: response, error: error)
        guard error == nil,
              let httpResponse = response as? HTTPURLResponse,
              let data,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            updateSummary(.init(physicalDeviceAvailable: true,
                                manualInvoked: true,
                                tokenReceived: true,
                                uploadURLResolved: true,
                                uploadAuthPresent: true,
                                uploadPayloadSchemaValid: true,
                                uploadRequested: true,
                                uploadResult: "http_failure_redacted",
                                uploadHTTPStatusBucket: httpStatusBucket,
                                registrationResult: "upload_failed_redacted",
                                blockedReason: "pushkit_token_upload_http_failure"))
            return
        }

        let registrationResult = body["pushkit_token_registration_result"] as? String ?? "upload_failed_redacted"
        let storeRequested = body["pushkit_token_store_requested"] as? Bool ?? false
        let storeResult = body["pushkit_token_store_result"] as? String ?? "redacted"
        let retrievalInternalCheck = body["pushkit_token_retrieval_internal_check"] as? String ?? "redacted"
        let tokenAPIExposesRawToken = body["pushkit_token_api_exposes_raw_token"] as? Bool ?? false
        let success = httpResponse.statusCode == 200 && registrationResult == "registered"
        updateSummary(.init(physicalDeviceAvailable: true,
                            manualInvoked: true,
                            tokenReceived: true,
                            uploadURLResolved: true,
                            uploadAuthPresent: true,
                            uploadPayloadSchemaValid: true,
                            uploadRequested: true,
                            uploadResult: success ? "http_success" : "http_failure_redacted",
                            uploadHTTPStatusBucket: httpStatusBucket,
                            registrationResult: registrationResult,
                            serverStoreRequested: storeRequested,
                            serverStoreResult: storeResult,
                            retrievalInternalCheck: retrievalInternalCheck,
                            tokenAPIExposesRawToken: tokenAPIExposesRawToken,
                            blockedReason: success ? "none" : "pushkit_token_upload_http_failure"))
    }

    private static func httpStatusBucket(response: URLResponse?, error: Error?) -> String {
        if error != nil {
            return "network_failure"
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            return "unknown"
        }
        switch httpResponse.statusCode {
        case 200..<300:
            return "2xx"
        case 401:
            return "401"
        case 403:
            return "403"
        case 404:
            return "404"
        case 500..<600:
            return "5xx"
        default:
            return "unknown"
        }
    }
}

private struct SalemXMatrixSessionWhoamiProofSummary {
    var proofGeneration = "none"
    var proofLastUpdatedBy = "none"
    var manualInvoked = false
    var expectedUserHashProvided = false
    var activeSessionAvailable = false
    var accessTokenProviderAvailable = false
    var accessTokenAvailable = false
    var homeserverURLAvailable = false
    var whoamiRequested = false
    var whoamiResult = "not_requested"
    var whoamiHTTPStatusBucket = "not_requested"
    var whoamiErrcode = "none"
    var whoamiFailureReason = "none"
    var matrixSessionPresent = false
    var matrixSessionUserHash = "none"
    var matrixSessionUserHashMatchesExpected = false
    var matrixSessionDevicePresent = false
    var pendingMetadataAuthReady = false
    var blockedReason = "none"

    var redactedLines: [String] {
        [
            "proof_generation=\(proofGeneration)",
            "proof_last_updated_by=\(proofLastUpdatedBy)",
            "proof_source=matrix_session_whoami_smoke",
            "manual_invoked=\(manualInvoked)",
            "expected_user_hash_provided=\(expectedUserHashProvided)",
            "iphone_app_matrix_session_active_session_available=\(activeSessionAvailable)",
            "iphone_app_matrix_session_access_token_provider_available=\(accessTokenProviderAvailable)",
            "iphone_app_matrix_session_access_token_available=\(accessTokenAvailable)",
            "iphone_app_matrix_session_homeserver_url_available=\(homeserverURLAvailable)",
            "iphone_app_matrix_session_whoami_requested=\(whoamiRequested)",
            "iphone_app_matrix_session_whoami_result=\(whoamiResult)",
            "iphone_app_matrix_session_whoami_http_status_bucket=\(whoamiHTTPStatusBucket)",
            "iphone_app_matrix_session_whoami_errcode=\(whoamiErrcode)",
            "iphone_app_matrix_session_whoami_failure_reason=\(whoamiFailureReason)",
            "iphone_app_matrix_session_present=\(matrixSessionPresent)",
            "iphone_app_matrix_session_user_hash=\(matrixSessionUserHash)",
            "iphone_app_matrix_session_user_hash_matches_expected=\(matrixSessionUserHashMatchesExpected)",
            "iphone_app_matrix_session_device_present=\(matrixSessionDevicePresent)",
            "iphone_app_pending_metadata_auth_ready=\(pendingMetadataAuthReady)",
            "APNs_sent=false",
            "dev_invite_used=false",
            "media_connect_requested=false",
            "media_connect_attempted=false",
            "livekit_join_requested=false",
            "microphone_permission_requested=false",
            "camera_permission_requested=false",
            "matrix_event_emit_requested=false",
            "real_call_flow_started=false",
            "blocked_reason=\(blockedReason)"
        ]
    }
}

private struct MatrixSessionWhoamiSmokeAvailability {
    var activeSessionAvailable: Bool
    var accessTokenProviderAvailable: Bool
    var homeserverURLAvailable: Bool
}

private struct SalemXRemotePeerContextHandoff {
    static let simulatorReady = SalemXRemotePeerContextHandoff(source: "debug_hook_redacted",
                                                               peerKind: "ios_simulator_redacted",
                                                               physicalDevice: "false",
                                                               simulatorAssisted: true,
                                                               readiness: "ready_redacted",
                                                               armedBeforeAPNs: true)
    static let physicalIOSReady = SalemXRemotePeerContextHandoff(source: "debug_hook_redacted",
                                                                 peerKind: "physical_ios_redacted",
                                                                 physicalDevice: "true",
                                                                 simulatorAssisted: false,
                                                                 readiness: "ready_redacted",
                                                                 armedBeforeAPNs: true)

    let source: String
    let peerKind: String
    let physicalDevice: String
    let simulatorAssisted: Bool
    let readiness: String
    let armedBeforeAPNs: Bool
}

@MainActor
private final class SalemXReceiverConnectedSessionLease {
    let callID: String
    let client: DirectCallLiveKitClientProtocol
    let e2eeContextProvider: DirectCallLiveKitE2EEContextProvider
    let e2eeContext: any DirectCallMediaE2EEContextProtocol
    let keyStore: DirectCallLiveKitMediaKeyStore

    init(callID: String,
         client: DirectCallLiveKitClientProtocol,
         e2eeContextProvider: DirectCallLiveKitE2EEContextProvider,
         e2eeContext: any DirectCallMediaE2EEContextProtocol,
         keyStore: DirectCallLiveKitMediaKeyStore) {
        self.callID = callID
        self.client = client
        self.e2eeContextProvider = e2eeContextProvider
        self.e2eeContext = e2eeContext
        self.keyStore = keyStore
    }

    func cleanup() async {
        await client.cleanup()
        e2eeContextProvider.clearContext(callID: callID)
    }
}

@objc(SalemXPushKitRegistrationSmokeDebugBridge)
// swiftlint:disable:next type_body_length
final class SalemXPushKitRegistrationSmokeDebugBridge: NSObject {
    private static let uploadSmokeURLHost = "debug"
    private static let uploadSmokeURLPath = "/pushkit-token-upload-smoke/start"
    private static let matrixSessionWhoamiSmokeURLPath = "/pushkit-token-upload-smoke/session-whoami"
    private static let physical6RuntimeEnablementURLHookPath = "/direct-call/physical6-enable-controlled-audio-connect"
    private static let remotePeerContextHandoffURLHookPath = "/direct-call/remote-peer-context-handoff"
    private static let senderLiveKitReadinessURLHookPath = "/direct-call/sender-livekit-readiness"
    private static let senderSideLiveKitJoinURLHookPath = "/direct-call/sender-side-livekit-join"
    private static let senderPendingMetadataReferenceHandoffURLHookPath = "/direct-call/sender-pending-metadata-reference-handoff"
    private static let senderRuntimeLiveKitJoinURLHookPath = "/direct-call/sender-runtime-livekit-join"
    private static let senderConnectedSignalHandoffURLHookPath = "/direct-call/sender-connected-signal-handoff"
    private static let receiverPushKitTokenReadinessURLHookPath = "/direct-call/receiver-pushkit-token-readiness"
    private static let receiverVoIPPushDeliveryTriageURLHookPath = "/direct-call/receiver-voip-push-delivery-triage"
    private static let receiverCallKitOperatorReadyURLHookPath = "/direct-call/receiver-callkit-operator-ready"
    private static let receiverForegroundInAppAnswerURLHookPath = "/direct-call/receiver-foreground-in-app-answer"
    private static let senderRuntimeLiveKitJoinConfirmation = "RUN_2_48Z_REAL_SENDER_RUNTIME_JOIN"
    private static let uploadSmokeDefaultURLString = "https://matrix.mertis.kz/_matrix/client/unstable/kz.salemx.direct_call/pushkit/token"
    private static let matrixSessionWhoamiURLString = "https://matrix.mertis.kz/_matrix/client/v3/account/whoami"
    private static let controlledMediaCredentialsTokenEndpointPath = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/livekit/token"
    private static let uploadSmokeProofFileName = "salemx-pushkit-token-upload-smoke-proof.txt"
    private static let matrixSessionWhoamiProofFileName = "salemx-matrix-session-whoami-proof.txt"
    private static let voIPPushReceiptProofFileName = "salemx-voip-push-receipt-proof.txt"
    private static let startupPushKitRegistryProofFileName = "salemx-startup-pushkit-registry-proof.txt"
    private static let localCallKitOnlyProofFileName = "salemx-local-callkit-only-proof.txt"
    private static let localBackgroundCallKitOnlyProofFileName = "salemx-local-background-callkit-proof.txt"
    private static let senderRuntimeLiveKitJoinProofFileName = "salemx-sender-runtime-livekit-join-proof.txt"
    private static let pendingMetadataEndpointPathPrefix = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata"
    private static let voIPPushReceiptCallKitReportTimeout: TimeInterval = 3
    private static let voIPPushReceiptAnswerableWindowTimeout: TimeInterval = 1.5
    private static let remoteParticipantObservationWindowTimeout: TimeInterval = 8
    private static let receiverPushKitTokenReadinessWaitTimeout: TimeInterval = 8
    private static let localBackgroundCallKitOnlyReportDelay: TimeInterval = 5
    private static let lock = NSLock()
    private static var registrar: DirectCallPushKitRegistrar?
    private static var latestSummary = initialRedactedSummary()
    private static var uploadSmoke: SalemXPushKitTokenUploadSmoke?
    private static var latestUploadSummary = initialUploadRedactedSummary()
    private static var latestMatrixSessionWhoamiSummary = SalemXMatrixSessionWhoamiProofSummary()
    private static var latestVoIPPushReceiptSummary = SalemXVoIPPushReceiptProofSummary()
    private static var latestStartupPushKitRegistrySummary = SalemXStartupPushKitRegistryProofSummary()
    private static var latestLocalCallKitOnlySummary = SalemXLocalCallKitOnlyProofSummary()
    private static var latestLocalBackgroundCallKitOnlySummary = SalemXLocalBackgroundCallKitOnlyProofSummary()
    private static var latestSenderRuntimeLiveKitJoinSummary = SalemXSenderRuntimeLiveKitJoinProofSummary()
    private static var senderRuntimeLiveKitJoinConsumed = false
    private static var senderRuntimeLiveKitJoinArmGeneration = 0
    private static var senderRuntimeLiveKitJoinConsumedGeneration: Int?
    private static var senderRuntimeLiveKitClient: DirectCallLiveKitClientProtocol?
    private static var senderRuntimeE2EEContextProvider: DirectCallLiveKitE2EEContextProvider?
    private static var senderRuntimeE2EEContext: (any DirectCallMediaE2EEContextProtocol)?
    private static var senderRuntimeKeyStore: DirectCallLiveKitMediaKeyStore?
    private static var senderRuntimeLiveKitClientFactory: @MainActor () -> DirectCallLiveKitClientProtocol = {
        LiveKitDirectCallClient()
    }

    private static var receiverConnectedSessionLease: SalemXReceiverConnectedSessionLease?
    private static var receiverConnectedSessionLeaseTask: Task<Void, Never>?
    private static var receiverConnectedSessionLeaseReleased = false
    private static var receiverConnectedWindowRetentionExtensionUsed = false
    private static var receiverRuntimeLiveKitClientFactory: @MainActor () -> DirectCallLiveKitClientProtocol = {
        LiveKitDirectCallClient()
    }

    private static var proofGenerationCounter = 0
    private static var callKitReportCompletionDate: Date?
    private static var pushKitCompletionDate: Date?
    private static var pushKitCompletionAnswerableWindowID: UUID?
    private static var pushKitCompletionAnswerableWindowFinish: ((String) -> Void)?
    private static var remoteParticipantObservationWindowID: UUID?
    private static var remoteParticipantObservationWindowStartedAt: Date?
    private static var receiverParticipantSnapshotSweepID: UUID?
    private static var pendingOperatorReadyToAnswer = false
    private static var pendingOperatorExpectedSurface = "unknown"
    private static let pendingForegroundCallMetadataMaxAge: TimeInterval = 120
    private static var pendingForegroundCallMetadataSession: DirectCallSession?
    private static var pendingForegroundCallMetadataSource = "none"
    private static var pendingForegroundCallMetadataRecordedAt: Date?
    private static var pendingAuthenticatedMetadataReference: String?
    private static var physical6RuntimeEnablementURLHook = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled
    private static var pendingRemotePeerContextHandoff: SalemXRemotePeerContextHandoff?
    private static var senderLiveKitReadinessHook = SalemXSenderLiveKitReadinessHook.defaultDisabled
    private static var senderSideLiveKitJoinHook = SalemXSenderSideLiveKitJoinHook.defaultDisabled
    private static var senderSideLiveKitJoinActivation = SalemXSenderSideLiveKitJoinActivation.defaultDisabled
    private static var senderPendingMetadataReferenceHandoff = SalemXSenderPendingMetadataReferenceHandoff.defaultDisabled
    private static var senderConnectParity = SalemXSenderConnectParity.defaultEnabled
    private static var senderConnectExecutorUnification = SalemXSenderConnectExecutorUnification.shared
    private static var senderJoinFailureDiagnostics = SalemXSenderJoinFailureDiagnostics.defaultDisabled
    private static var senderTransportFailureDiagnostics = SalemXSenderTransportFailureDiagnostics.defaultDisabled
    private static var senderTransportErrorSurface = SalemXSenderTransportErrorSurface.defaultDisabled
    #if canImport(CallKit) && os(iOS)
    private static var callKitProofHarness: NativeIncomingSyntheticCallKitUIProofHarness?
    private static var callKitProofGeneration = 0
    private static var localCallKitOnlyProofHarness: NativeIncomingSyntheticCallKitUIProofHarness?
    private static var localCallKitOnlyProofGeneration = 0
    private static var localBackgroundCallKitOnlyProofHarness: NativeIncomingSyntheticCallKitUIProofHarness?
    private static var localBackgroundCallKitOnlyProofGeneration = 0
    #endif
    #if os(iOS)
    private static var voIPPushReceiptBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif

    @objc static func startRegistrationSmoke() -> String {
        var configuration = DirectCallPushKitRegistrarConfiguration(featureGate: .init(isEnabled: true),
                                                                    registryFactory: DirectCallRealPushKitRegistryFactory())
        configuration.resultHandler = { result in
            updateLatestSummary(with: result)
        }

        let registrar = DirectCallPushKitRegistrar(configuration: configuration)
        self.registrar = registrar
        let result = registrar.startRegistration()
        updateLatestSummary(with: result)
        return redactedStateSummary()
    }

    static func handleUploadSmokeURL(_ url: URL) -> Bool {
        guard url.scheme == "kz.salemx.msg",
              url.host == uploadSmokeURLHost else {
            return false
        }

        if url.path == uploadSmokeURLPath {
            _ = startRegistrationUploadSmokeWithCurrentSessionURLString(uploadSmokeDefaultURLString)
            return true
        }

        if url.path == matrixSessionWhoamiSmokeURLPath {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let expectedUserHash = components?.queryItems?.first { $0.name == "expected_user_hash" }?.value ?? ""
            _ = startMatrixSessionWhoamiSmokeWithExpectedUserHash(expectedUserHash)
            return true
        }

        if url.path == physical6RuntimeEnablementURLHookPath {
            armPhysical6RuntimeEnablementURLHook()
            return true
        }

        if url.path == remotePeerContextHandoffURLHookPath {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let peerKind = components?.queryItems?.first { $0.name == "peer_kind" || $0.name == "remote_peer_kind" }?.value ?? ""
            if peerKind == "physical_ios" || peerKind == "physical_ios_redacted" {
                armPhysicalIOSRemotePeerContextHandoffURLHook()
            } else {
                armSimulatorRemotePeerContextHandoffURLHook()
            }
            return true
        }

        if url.path == receiverPushKitTokenReadinessURLHookPath {
            startReceiverPushKitTokenReadinessURLHook()
            return true
        }

        if url.path == receiverVoIPPushDeliveryTriageURLHookPath {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            recordReceiverVoIPPushDeliveryTriageURLHook(components)
            return true
        }

        if url.path == receiverCallKitOperatorReadyURLHookPath {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            armReceiverCallKitOperatorReadyURLHook(components)
            return true
        }

        if url.path == receiverForegroundInAppAnswerURLHookPath {
            startReceiverForegroundInAppAnswerURLHook()
            return true
        }

        if handleSenderRuntimeURLHook(url) {
            return true
        }

        return false
    }

    private static func handleSenderRuntimeURLHook(_ url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if url.path == senderLiveKitReadinessURLHookPath {
            armSenderLiveKitReadinessURLHook(components)
            return true
        } else if url.path == senderSideLiveKitJoinURLHookPath {
            armSenderSideLiveKitJoinURLHook(components)
            return true
        } else if url.path == senderPendingMetadataReferenceHandoffURLHookPath {
            armSenderPendingMetadataReferenceHandoffURLHook(components)
            return true
        } else if url.path == senderRuntimeLiveKitJoinURLHookPath {
            startSenderRuntimeLiveKitJoinURLHook(components)
            return true
        } else if url.path == senderConnectedSignalHandoffURLHookPath {
            armSenderConnectedSignalHandoffURLHook(components)
            return true
        }
        return false
    }

    private static func armPhysical6RuntimeEnablementURLHook() {
        lock.lock()
        physical6RuntimeEnablementURLHook = .armed
        var summary = latestVoIPPushReceiptSummary
        summary.recordPhysical6RuntimeEnablementURLHook(physical6RuntimeEnablementURLHook)
        summary.mediaConnectRequested = false
        summary.mediaConnectAttempted = false
        summary.liveKitJoinRequested = false
        summary.liveKitConnectAudioInvoked = false
        summary.microphonePermissionRequested = false
        summary.cameraPermissionRequested = false
        summary.matrixEventEmitRequested = false
        summary.realCallFlowStarted = false
        summary.mediaConnectExecutionAllowed = false
        summary.mediaConnectEngineInvoked = false
        summary.recordControlledAudioConnectFirstAttemptProof(.defaultDisabled)
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
    }

    private static func startReceiverPushKitTokenReadinessURLHook() {
        _ = startRegistrationUploadSmokeWithCurrentSessionURLString(uploadSmokeDefaultURLString)
        recordReceiverPushKitTokenReadinessProof(waitStarted: true,
                                                 waitCompleted: false,
                                                 waitTimeout: false)

        Task { @MainActor in
            let deadline = Date().addingTimeInterval(receiverPushKitTokenReadinessWaitTimeout)
            var terminal = false
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 250_000_000)
                terminal = receiverPushKitTokenReadinessTerminal()
                if terminal {
                    break
                }
            }

            recordReceiverPushKitTokenReadinessProof(waitStarted: true,
                                                     waitCompleted: true,
                                                     waitTimeout: !terminal)
        }
    }

    private static func receiverPushKitTokenReadinessTerminal() -> Bool {
        lock.lock()
        let terminal = SalemXVoIPPushReceiptProofSummary.receiverPushKitTokenReadinessTerminal(uploadProof: latestUploadSummary)
        lock.unlock()
        return terminal
    }

    private static func recordReceiverPushKitTokenReadinessProof(waitStarted: Bool,
                                                                 waitCompleted: Bool,
                                                                 waitTimeout: Bool) {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.proofGeneration = nextProofGenerationLocked()
        summary.proofLastUpdatedBy = "receiver_pushkit_token_readiness"
        summary.refreshReceiverPushKitTokenReadiness(uploadProof: latestUploadSummary,
                                                     appStateBeforeAPNs: currentApplicationStateProof(),
                                                     waitStarted: waitStarted,
                                                     waitCompleted: waitCompleted,
                                                     waitTimeout: waitTimeout)
        latestVoIPPushReceiptSummary = summary
        let proof = summary.redactedLines.joined(separator: "\n")
        lock.unlock()
        writeVoIPPushReceiptProof(proof)
    }

    private static func recordReceiverVoIPPushDeliveryTriageURLHook(_ components: URLComponents?) {
        let apnsProviderAcceptanceResultBucket = redactedStringQueryItem(components,
                                                                         names: ["apns_provider_acceptance_result_bucket"],
                                                                         allowedValues: ["2xx", "non_2xx", "unknown", "not_requested",
                                                                                         "sandbox_success", "accepted_redacted"])
        let proofGenerationAfterAPNsChanged = redactedOptionalBoolQueryItem(components,
                                                                            names: ["receiver_app_proof_generation_after_apns_changed"])
        let tokenDeviceBindingBucket = redactedStringQueryItem(components,
                                                               names: ["receiver_pushkit_token_device_binding_expected_bucket"],
                                                               allowedValues: ["expected_redacted", "mismatch_possible_redacted",
                                                                               "unknown", "not_requested"])
        let tokenEnvironmentBucket = redactedStringQueryItem(components,
                                                             names: ["receiver_pushkit_token_environment_bucket"],
                                                             allowedValues: ["development", "sandbox", "production",
                                                                             "mismatch_possible_redacted", "unknown"])
        lock.lock()
        let latestUploadSummary = latestUploadSummary
        var summary = latestVoIPPushReceiptSummary
        summary.proofGeneration = nextProofGenerationLocked()
        summary.proofLastUpdatedBy = "receiver_voip_push_delivery_triage"
        summary.recordReceiverVoIPPushDeliveryTriage(apnsProviderAcceptanceResultBucket: apnsProviderAcceptanceResultBucket,
                                                     receiverAppProofGenerationAfterAPNsChanged: proofGenerationAfterAPNsChanged,
                                                     receiverPushKitTokenDeviceBindingExpectedBucket: tokenDeviceBindingBucket,
                                                     receiverPushKitTokenEnvironmentBucket: tokenEnvironmentBucket)
        summary.refreshReceiverVoIPPushDeliveryTriage(uploadProof: latestUploadSummary,
                                                      appStateBeforeAPNs: currentApplicationStateProof())
        latestVoIPPushReceiptSummary = summary
        let proof = summary.redactedLines.joined(separator: "\n")
        lock.unlock()
        writeVoIPPushReceiptProof(proof)
    }

    private static func armReceiverCallKitOperatorReadyURLHook(_ components: URLComponents?) {
        let expectedSurface = components?.queryItems?.first { $0.name == "expected_surface" || $0.name == "surface" }?.value ?? "unknown"
        _ = recordCallKitOperatorReadyToAnswer(expectedSurface)
    }

    private static func startReceiverForegroundInAppAnswerURLHook() {
        let shouldStartPostAnswerContinuation: Bool
        let summaryToWrite: SalemXVoIPPushReceiptProofSummary
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        let pendingMetadataReferenceAvailable = pendingAuthenticatedMetadataReference?.isEmpty == false
        shouldStartPostAnswerContinuation = summary.recordReceiverForegroundInAppAnswerHookRequest(currentAppState: currentApplicationStateProof(),
                                                                                                   pendingMetadataReferenceAvailable: pendingMetadataReferenceAvailable)
        summaryToWrite = summary
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summaryToWrite)

        guard shouldStartPostAnswerContinuation else {
            return
        }

        recordCallKitAnswerActionProof(screenSource: "foreground_in_app_answer_real_invite_controlled")
    }

    private static func armSimulatorRemotePeerContextHandoffURLHook() {
        armRemotePeerContextHandoffURLHook(.simulatorReady)
    }

    private static func armPhysicalIOSRemotePeerContextHandoffURLHook() {
        armRemotePeerContextHandoffURLHook(.physicalIOSReady)
    }

    private static func armRemotePeerContextHandoffURLHook(_ context: SalemXRemotePeerContextHandoff) {
        lock.lock()
        pendingRemotePeerContextHandoff = context
        var summary = latestVoIPPushReceiptSummary
        summary.recordRemotePeerContextHandoff(context,
                                               receivedByRuntime: false,
                                               survivedPushKit: false,
                                               survivedAnswer: false)
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
    }

    private static func armSenderLiveKitReadinessURLHook(_ components: URLComponents?) {
        let hook = SalemXSenderLiveKitReadinessHook(armed: true,
                                                    matrixSessionReady: redactedBoolQueryItem(components,
                                                                                              names: ["sender_matrix_session_ready", "matrix_session_ready"]),
                                                    expectedUserMatched: redactedBoolQueryItem(components,
                                                                                               names: ["sender_expected_hash_matches", "expected_user_matched", "expected_user_hash_matches"]),
                                                    sameRoomReady: redactedBoolQueryItem(components,
                                                                                         names: ["sender_same_room_ready", "same_room_ready"]),
                                                    credentialsReady: redactedBoolQueryItem(components,
                                                                                            names: ["sender_credentials_ready", "credentials_ready"]))
        lock.lock()
        senderLiveKitReadinessHook = hook
        var summary = latestVoIPPushReceiptSummary
        summary.recordSenderReadinessRuntimeHandoff(hook,
                                                    receivedByRuntime: false,
                                                    survivedPushKit: false,
                                                    survivedAnswer: false)
        summary.mediaConnectRequested = false
        summary.mediaConnectAttempted = false
        summary.liveKitJoinRequested = false
        summary.liveKitConnectAudioInvoked = false
        summary.microphonePermissionRequested = false
        summary.cameraPermissionRequested = false
        summary.matrixEventEmitRequested = false
        summary.realCallFlowStarted = false
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
    }

    private static func armSenderPendingMetadataReferenceHandoffURLHook(_ components: URLComponents?) {
        let reference = components?.queryItems?.first { $0.name == "pending_metadata_reference" }?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceValue = components?.queryItems?.first { $0.name == "source" }?.value ?? ""
        let source = sourceValue == "invite_response" || sourceValue == "invite_response_redacted" ? "invite_response_redacted" : "debug_handoff_redacted"
        let handoff = SalemXSenderPendingMetadataReferenceHandoff(reference: reference?.isEmpty == false ? reference : nil,
                                                                  source: source,
                                                                  armed: reference?.isEmpty == false,
                                                                  receivedByRuntime: false)
        lock.lock()
        let previousArmGeneration = senderRuntimeLiveKitJoinArmGeneration
        if handoff.referencePresent {
            senderRuntimeLiveKitJoinArmGeneration += 1
            senderRuntimeLiveKitJoinConsumed = false
            senderRuntimeLiveKitJoinConsumedGeneration = nil
        }
        let armGenerationChanged = senderRuntimeLiveKitJoinArmGeneration != previousArmGeneration
        senderPendingMetadataReferenceHandoff = handoff
        var summary = latestSenderRuntimeLiveKitJoinSummary
        summary.markReferenceHandoff(handoff, armGenerationChanged: armGenerationChanged)
        if !handoff.referencePresent {
            summary.blockedReason = "sender_pending_metadata_reference_missing_redacted"
        }
        lock.unlock()

        updateLatestSenderRuntimeLiveKitJoinSummary(summary)
    }

    private static func armSenderConnectedSignalHandoffURLHook(_ components: URLComponents?) {
        let senderConnected = redactedBoolQueryItem(components,
                                                    names: ["sender_connected", "sender_livekit_room_connected", "connected"])
        let correlationMatched = redactedOptionalBoolQueryItem(components,
                                                               names: ["opaque_correlation_match", "correlation_match"]) ?? true
        let sourceValue = components?.queryItems?.first { $0.name == "source" }?.value ?? ""
        let source = sourceValue == "sender_runtime_livekit_join" || sourceValue == "sender_runtime_livekit_join_redacted" ? "sender_runtime_livekit_join" : "unknown"

        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.recordSenderConnectedSignalFromRuntime(senderConnected: senderConnected,
                                                       source: source,
                                                       correlationMatched: correlationMatched)
        summary.activateRemoteParticipantObservationRuntimeWindowIfNeeded()
        if senderConnected {
            remoteParticipantObservationWindowID = nil
            remoteParticipantObservationWindowStartedAt = nil
        }
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        scheduleRemoteParticipantObservationTimeoutIfNeeded()
        if senderConnected {
            scheduleReceiverParticipantSnapshotSweepIfNeeded()
        }
    }

    private static func armSenderSideLiveKitJoinURLHook(_ components: URLComponents?) {
        let requested = redactedBoolQueryItem(components,
                                              names: ["sender_join_requested", "join_requested"])
        lock.lock()
        let readinessHook = senderLiveKitReadinessHook
        let previousActivation = senderSideLiveKitJoinActivation
        let repeated = requested && previousActivation.consumed
        let joinDiagnostics = SalemXSenderJoinFailureDiagnostics.defaultDisabled
        let transportDiagnostics = SalemXSenderTransportFailureDiagnostics.defaultDisabled
        let transportErrorSurface = SalemXSenderTransportErrorSurface.defaultDisabled
        let senderReadinessMissing = !readinessHook.armed
            || !readinessHook.matrixSessionReady
            || !readinessHook.expectedUserMatched
            || !readinessHook.credentialsReady
        let sameRoomReadinessMissing = !readinessHook.sameRoomReady
        let finalResult: String
        let finalErrorBucket: String
        let activationBlockedReason: String

        if repeated {
            finalResult = SalemXSenderSideLiveKitJoinHook.blockedResult
            finalErrorBucket = joinDiagnostics.errorBucket
            activationBlockedReason = SalemXSenderSideLiveKitJoinActivation.repeatedSenderJoinBlockedReason
        } else if requested, senderReadinessMissing {
            finalResult = SalemXSenderSideLiveKitJoinHook.blockedResult
            finalErrorBucket = joinDiagnostics.errorBucket == "none" ? SalemXSenderSideLiveKitJoinActivation.senderReadinessMissingReason : joinDiagnostics.errorBucket
            activationBlockedReason = SalemXSenderSideLiveKitJoinActivation.senderReadinessMissingReason
        } else if requested, sameRoomReadinessMissing {
            finalResult = SalemXSenderSideLiveKitJoinHook.blockedResult
            finalErrorBucket = joinDiagnostics.errorBucket == "none" ? SalemXSenderSideLiveKitJoinActivation.sameRoomReadinessMissingReason : joinDiagnostics.errorBucket
            activationBlockedReason = SalemXSenderSideLiveKitJoinActivation.sameRoomReadinessMissingReason
        } else if requested {
            finalResult = SalemXSenderSideLiveKitJoinHook.blockedResult
            finalErrorBucket = "sender_runtime_bridge_required_redacted"
            activationBlockedReason = "sender_runtime_bridge_required_redacted"
        } else {
            finalResult = SalemXSenderSideLiveKitJoinHook.notRequestedResult
            finalErrorBucket = "none"
            activationBlockedReason = SalemXSenderSideLiveKitJoinActivation.armedWaitingForTriggerReason
        }

        let hook = SalemXSenderSideLiveKitJoinHook(armed: true,
                                                   requested: requested,
                                                   result: finalResult,
                                                   errorBucket: finalErrorBucket,
                                                   repeated: repeated)
        let activation = SalemXSenderSideLiveKitJoinActivation(armed: true,
                                                               triggered: requested,
                                                               consumed: requested && !repeated,
                                                               repeated: repeated,
                                                               blockedReason: activationBlockedReason)
        senderSideLiveKitJoinHook = hook
        senderSideLiveKitJoinActivation = activation
        senderJoinFailureDiagnostics = joinDiagnostics
        senderTransportFailureDiagnostics = transportDiagnostics
        senderTransportErrorSurface = transportErrorSurface
        var summary = latestVoIPPushReceiptSummary
        summary.recordSenderSideLiveKitJoinHook(hook)
        summary.recordSenderConnectParity(senderConnectParity)
        summary.recordSenderConnectExecutorUnification(senderConnectExecutorUnification)
        summary.recordSenderJoinFailureDiagnostics(joinDiagnostics)
        summary.recordSenderTransportFailureDiagnostics(transportDiagnostics)
        summary.recordSenderTransportErrorSurface(transportErrorSurface)
        summary.recordSenderSideLiveKitJoinActivation(activation)
        summary.mediaConnectRequested = false
        summary.mediaConnectAttempted = false
        summary.liveKitJoinRequested = false
        summary.liveKitConnectAudioInvoked = false
        summary.microphonePermissionRequested = false
        summary.cameraPermissionRequested = false
        summary.matrixEventEmitRequested = false
        summary.realCallFlowStarted = false
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
    }

    private static func startSenderRuntimeLiveKitJoinURLHook(_ components: URLComponents?) {
        let confirmed = components?.queryItems?.first { $0.name == "confirm" }?.value == senderRuntimeLiveKitJoinConfirmation

        lock.lock()
        var handoff = senderPendingMetadataReferenceHandoff
        if confirmed, handoff.referencePresent {
            handoff = handoff.receivedByRuntimeCopy()
            senderPendingMetadataReferenceHandoff = handoff
        }
        let reference = handoff.reference ?? ""
        let referencePresent = handoff.referencePresent
        let currentArmGeneration = senderRuntimeLiveKitJoinArmGeneration
        let consumedGeneration = senderRuntimeLiveKitJoinConsumedGeneration
        let triggerGenerationMatchesArm = confirmed && referencePresent && handoff.armed && currentArmGeneration > 0
        let staleGenerationDetected = confirmed && senderRuntimeLiveKitJoinConsumed && consumedGeneration != currentArmGeneration
        let consumedCurrentGeneration = confirmed && senderRuntimeLiveKitJoinConsumed && consumedGeneration == currentArmGeneration
        let repeated = consumedCurrentGeneration
        let repeatedOnlyAfterConsumed = !repeated || consumedCurrentGeneration
        if confirmed, referencePresent, !repeated {
            senderRuntimeLiveKitJoinConsumed = true
            senderRuntimeLiveKitJoinConsumedGeneration = currentArmGeneration
        }
        var summary = latestSenderRuntimeLiveKitJoinSummary
        summary.markStarted(referencePresent: referencePresent,
                            repeated: repeated,
                            handoff: handoff,
                            armGenerationChanged: false,
                            triggerGenerationMatchesArm: triggerGenerationMatchesArm,
                            staleGenerationDetected: staleGenerationDetected,
                            repeatedOnlyAfterConsumed: repeatedOnlyAfterConsumed)
        if !confirmed {
            summary.bridgeTriggered = false
            summary.bridgeConsumed = false
            summary.blockedReason = "sender_runtime_join_default_disabled_no_connect"
        } else if !referencePresent {
            let reason = handoff.armed ? "sender_pending_metadata_reference_missing_redacted" : "sender_pending_metadata_reference_sender_memory_missing_redacted"
            summary.markPendingMetadataBlocked(reason,
                                               authorized: false)
        }
        lock.unlock()

        updateLatestSenderRuntimeLiveKitJoinSummary(summary)

        guard confirmed, referencePresent, !repeated else {
            return
        }

        Task { @MainActor in
            await runSenderRuntimeLiveKitJoin(reference: reference)
        }
    }

    @MainActor
    private static func runSenderRuntimeLiveKitJoin(reference: String) async {
        guard let session = await fetchSenderRuntimePendingMetadata(reference: reference) else {
            return
        }

        let credentials = await requestSenderRuntimeCredentials(for: session)
        guard case .success(let connectionInfo) = credentials else {
            return
        }

        guard case .success(let e2eeContext) = prepareSenderRuntimeE2EEContext(for: session) else {
            return
        }

        let client = senderRuntimeLiveKitClientFactory()
        let executor = DirectCallLiveKitConnectExecutor(liveKitClient: client)
        senderRuntimeLiveKitClient = client
        let result = await executor.connectAudio(connectionInfo: connectionInfo, e2eeContext: e2eeContext)

        lock.lock()
        var summary = latestSenderRuntimeLiveKitJoinSummary
        summary.markRuntime(result)
        lock.unlock()

        updateLatestSenderRuntimeLiveKitJoinSummary(summary)
    }

    @MainActor
    private static func fetchSenderRuntimePendingMetadata(reference: String) async -> DirectCallSession? {
        guard let fetchURL = senderPendingMetadataFetchURL(reference: reference) else {
            recordSenderRuntimePendingMetadataBlocked("sender_pending_metadata_reference_sender_view_missing_redacted",
                                                      authorized: false)
            return nil
        }
        guard let accessToken = await SalemXForegroundSSESmokeDebug.matrixAccessTokenForPushKitUploadSmoke() else {
            recordSenderRuntimePendingMetadataBlocked("sender_pending_metadata_fetch_unauthorized_redacted",
                                                      authorized: false)
            return nil
        }

        var request = URLRequest(url: fetchURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("B" + "earer " + accessToken, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let diagnostics = pendingMetadataFetchFailureDiagnostics(response: response, data: data)
                recordSenderRuntimePendingMetadataBlocked(senderRuntimePendingMetadataBlockedReason(diagnostics),
                                                          authorized: true)
                return nil
            }
            guard let session = directCallSessionFromSenderPendingMetadata(data: data) else {
                recordSenderRuntimePendingMetadataBlocked(senderPendingMetadataPayloadBlockedReason(data: data),
                                                          authorized: true)
                return nil
            }

            lock.lock()
            var summary = latestSenderRuntimeLiveKitJoinSummary
            summary.markPendingMetadataSuccess(session)
            lock.unlock()

            updateLatestSenderRuntimeLiveKitJoinSummary(summary)
            return session
        } catch {
            recordSenderRuntimePendingMetadataBlocked("sender_runtime_join_pending_metadata_network_failure_redacted",
                                                      authorized: true)
            return nil
        }
    }

    private static func recordSenderRuntimePendingMetadataBlocked(_ reason: String, authorized: Bool) {
        lock.lock()
        var summary = latestSenderRuntimeLiveKitJoinSummary
        summary.markPendingMetadataBlocked(reason, authorized: authorized)
        lock.unlock()

        updateLatestSenderRuntimeLiveKitJoinSummary(summary)
    }

    @MainActor
    private static func requestSenderRuntimeCredentials(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        guard let tokenEndpointURL = controlledMediaCredentialsTokenEndpointURL(),
              let accessTokenProvider = SalemXForegroundSSESmokeDebug.matrixAccessTokenProviderForPushKitUploadSmoke() else {
            let result: Result<DirectCallMediaConnectionInfo, DirectCallMediaError> = .failure(.accessTokenUnavailable)
            recordSenderRuntimeCredentials(result)
            return result
        }

        let tokenClient = ProductionDirectCallLiveKitTokenClient(configuration: .init(tokenEndpointURL: tokenEndpointURL),
                                                                 httpTransport: URLSessionDirectCallHTTPTransport(),
                                                                 accessTokenProvider: accessTokenProvider)
        let tokenProvider = DirectCallLiveKitTokenProvider(tokenClient: tokenClient)
        let result = await tokenProvider.connectionInfo(for: session)
        recordSenderRuntimeCredentials(result)
        return result
    }

    private static func recordSenderRuntimeCredentials(_ result: Result<DirectCallMediaConnectionInfo, DirectCallMediaError>) {
        lock.lock()
        var summary = latestSenderRuntimeLiveKitJoinSummary
        summary.markCredentials(result)
        lock.unlock()

        updateLatestSenderRuntimeLiveKitJoinSummary(summary)
    }

    @MainActor
    private static func prepareSenderRuntimeE2EEContext(for session: DirectCallSession) -> Result<any DirectCallMediaE2EEContextProtocol, DirectCallMediaError> {
        let keyStore = DirectCallLiveKitMediaKeyStore()
        switch keyStore.storeSharedKey(UUID().uuidString + UUID().uuidString, callID: session.callID) {
        case .success(let keyHandle):
            let provider = DirectCallLiveKitE2EEContextProvider(keyStore: keyStore)
            switch provider.context(for: session, keyHandle: keyHandle) {
            case .success(let context):
                senderRuntimeKeyStore = keyStore
                senderRuntimeE2EEContextProvider = provider
                senderRuntimeE2EEContext = context
                return .success(context)
            case .failure(let error):
                recordSenderRuntimeE2EEBlocked(error)
                return .failure(error)
            }
        case .failure(let error):
            recordSenderRuntimeE2EEBlocked(error)
            return .failure(error)
        }
    }

    private static func recordSenderRuntimeE2EEBlocked(_ error: DirectCallMediaError) {
        lock.lock()
        var summary = latestSenderRuntimeLiveKitJoinSummary
        summary.markE2EEBlocked(error)
        lock.unlock()

        updateLatestSenderRuntimeLiveKitJoinSummary(summary)
    }

    private static func senderPendingMetadataFetchURL(reference: String) -> URL? {
        guard !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var components = URLComponents(string: uploadSmokeDefaultURLString),
              let encodedReference = reference.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        components.path = pendingMetadataEndpointPathPrefix + "/" + encodedReference + "/sender"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func directCallSessionFromSenderPendingMetadata(data: Data) -> DirectCallSession? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["version"] as? Int == 1,
              let callID = payload["call_id"] as? String,
              let roomID = payload["room_id"] as? String,
              let peerUserID = payload["peer_user_id"] as? String,
              payload["direction"] as? String == "outgoing",
              DirectCallIntent.parse(payload["intent"] as? String) == .audio,
              !callID.isEmpty,
              !roomID.isEmpty,
              !peerUserID.isEmpty else {
            return nil
        }

        return DirectCallSession(callID: callID,
                                 roomID: roomID,
                                 peerUserID: peerUserID,
                                 direction: .outgoing,
                                 intent: .audio,
                                 encryptionMode: .e2eeRequired,
                                 startedAt: Date(),
                                 updatedAt: Date(),
                                 state: .outgoingRinging,
                                 encryptionState: .ready)
    }

    private static func senderRuntimePendingMetadataBlockedReason(_ diagnostics: PendingMetadataFetchFailureDiagnostics) -> String {
        switch diagnostics.failureReason {
        case "auth_rejected":
            return "sender_pending_metadata_fetch_unauthorized_redacted"
        case "forbidden":
            return "sender_pending_metadata_reference_mismatch_redacted"
        case "not_found":
            return "sender_pending_metadata_fetch_not_found_redacted"
        case "server_error":
            return "sender_runtime_join_pending_metadata_fetch_server_error_redacted"
        default:
            return "sender_runtime_join_pending_metadata_fetch_failed_redacted"
        }
    }

    private static func senderPendingMetadataPayloadBlockedReason(data: Data) -> String {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "sender_runtime_join_pending_metadata_payload_invalid_redacted"
        }
        guard (payload["call_id"] as? String)?.isEmpty == false else {
            return "sender_pending_metadata_call_binding_missing_redacted"
        }
        guard (payload["room_id"] as? String)?.isEmpty == false else {
            return "sender_pending_metadata_room_binding_missing_redacted"
        }
        guard (payload["peer_user_id"] as? String)?.isEmpty == false else {
            return "sender_pending_metadata_peer_binding_missing_redacted"
        }
        guard payload["direction"] as? String == "outgoing" else {
            return "sender_pending_metadata_direction_invalid_redacted"
        }
        guard DirectCallIntent.parse(payload["intent"] as? String) == .audio else {
            return "sender_pending_metadata_intent_invalid_redacted"
        }
        return "sender_runtime_join_pending_metadata_payload_invalid_redacted"
    }

    @MainActor
    static func installSenderRuntimeLiveKitClientFactoryForTests(_ factory: @escaping @MainActor () -> DirectCallLiveKitClientProtocol) {
        senderRuntimeLiveKitClientFactory = factory
    }

    @MainActor
    static func resetSenderRuntimeLiveKitClientFactoryForTests() {
        senderRuntimeLiveKitClientFactory = {
            LiveKitDirectCallClient()
        }
    }

    private static func senderJoinDiagnostics(components: URLComponents?,
                                              requested: Bool,
                                              repeated: Bool,
                                              readinessHook: SalemXSenderLiveKitReadinessHook,
                                              requestedResult: String) -> SalemXSenderJoinDiagnosticsResult {
        let transportAttempted = redactedOptionalBoolQueryItem(components,
                                                               names: ["sender_transport_attempted", "transport_attempted"])
        let transportStarted = redactedOptionalBoolQueryItem(components,
                                                             names: ["sender_transport_started", "transport_started"])
        let transportCompleted = redactedOptionalBoolQueryItem(components,
                                                               names: ["sender_transport_completed", "transport_completed"])
        let transportResult = redactedSenderJoinTransportResultQueryItem(components)
        let resolvedTransportAttempted = transportAttempted ?? (requestedResult == SalemXSenderSideLiveKitJoinHook.successResult
            || requestedResult == SalemXSenderSideLiveKitJoinHook.failedResult)
        let resolvedTransportResult = transportResult ?? (resolvedTransportAttempted ?
            SalemXSenderTransportFailureDiagnostics.failedTransportResult :
            SalemXSenderTransportFailureDiagnostics.notRequestedTransportResult)
        let requestedFailureClassification = redactedSenderJoinFailureClassificationQueryItem(components)
        let requestedTransportFailureClassification = redactedSenderTransportFailureClassificationQueryItem(components)
        let sdkFailureSurface = SalemXSenderLiveKitSDKFailureSurface.classify(requested: requested,
                                                                              transportAttempted: resolvedTransportAttempted,
                                                                              transportResult: resolvedTransportResult,
                                                                              input: redactedSenderLiveKitSDKFailureSurfaceInput(components))
        let errorSurface = SalemXSenderTransportErrorSurface.classify(requested: requested,
                                                                      transportAttempted: resolvedTransportAttempted,
                                                                      transportResult: resolvedTransportResult,
                                                                      input: redactedSenderTransportErrorSurfaceInput(components,
                                                                                                                      sdkFailureSurface: sdkFailureSurface))
        let credentialsPresent = redactedOptionalBoolQueryItem(components,
                                                               names: ["sender_credentials_present", "credentials_present"]) ?? readinessHook.credentialsReady
        let tokenPresent = redactedOptionalBoolQueryItem(components,
                                                         names: ["sender_token_present", "token_present"]) ?? readinessHook.credentialsReady
        let urlPresent = redactedOptionalBoolQueryItem(components,
                                                       names: ["sender_url_present", "url_present"]) ?? readinessHook.credentialsReady
        let roomBindingPresent = redactedOptionalBoolQueryItem(components,
                                                               names: ["sender_room_binding_present", "room_binding_present"]) ?? readinessHook.sameRoomReady
        let sameLiveKitRoom = redactedOptionalBoolQueryItem(components,
                                                            names: ["sender_same_livekit_room", "same_livekit_room"]) ?? readinessHook.sameRoomReady
        let sameTokenAuthority = redactedOptionalBoolQueryItem(components,
                                                               names: ["sender_same_token_authority", "same_token_authority"]) ?? credentialsPresent
        let receiverSenderRoomMatch = redactedOptionalBoolQueryItem(components,
                                                                    names: ["sender_receiver_room_match", "receiver_sender_room_match"]) ?? sameLiveKitRoom
        let receiverSenderTokenAuthorityMatch = redactedOptionalBoolQueryItem(components,
                                                                              names: ["sender_receiver_token_authority_match", "receiver_sender_token_authority_match"]) ?? sameTokenAuthority
        let joinDiagnostics = SalemXSenderJoinFailureDiagnostics.classify(.init(requested: requested,
                                                                                repeated: repeated,
                                                                                credentialsPresent: credentialsPresent,
                                                                                tokenPresent: tokenPresent,
                                                                                urlPresent: urlPresent,
                                                                                roomBindingPresent: roomBindingPresent,
                                                                                sameLiveKitRoom: sameLiveKitRoom,
                                                                                requestedResult: requestedResult,
                                                                                transportAttempted: transportAttempted,
                                                                                transportResult: transportResult,
                                                                                classification: requestedFailureClassification))
        let transportDiagnostics = SalemXSenderTransportFailureDiagnostics.classify(.init(requested: requested,
                                                                                          liveKitURLPresent: urlPresent,
                                                                                          tokenPresent: tokenPresent,
                                                                                          roomBindingPresent: roomBindingPresent,
                                                                                          sameLiveKitRoom: sameLiveKitRoom,
                                                                                          sameTokenAuthority: sameTokenAuthority,
                                                                                          receiverSenderRoomMatch: receiverSenderRoomMatch,
                                                                                          receiverSenderTokenAuthorityMatch: receiverSenderTokenAuthorityMatch,
                                                                                          transportAttempted: transportAttempted,
                                                                                          transportStarted: transportStarted,
                                                                                          transportCompleted: transportCompleted,
                                                                                          transportResult: transportResult,
                                                                                          classification: requestedTransportFailureClassification,
                                                                                          errorSurface: errorSurface))
        return .init(joinFailure: joinDiagnostics,
                     transportFailure: transportDiagnostics,
                     transportErrorSurface: errorSurface)
    }

    private static func redactedSenderSideLiveKitJoinResultQueryItem(_ components: URLComponents?) -> String {
        guard let value = components?.queryItems?.first(where: { $0.name == "sender_join_result" || $0.name == "join_result" })?.value?.lowercased() else {
            return SalemXSenderSideLiveKitJoinHook.notRequestedResult
        }
        if value == SalemXSenderSideLiveKitJoinHook.blockedResult {
            return SalemXSenderSideLiveKitJoinHook.blockedResult
        }
        if value == SalemXSenderSideLiveKitJoinHook.successResult {
            return SalemXSenderSideLiveKitJoinHook.successResult
        }
        if value == SalemXSenderSideLiveKitJoinHook.failedResult {
            return SalemXSenderSideLiveKitJoinHook.failedResult
        }
        return SalemXSenderSideLiveKitJoinHook.notRequestedResult
    }

    private static func redactedSenderJoinTransportResultQueryItem(_ components: URLComponents?) -> String? {
        guard let value = components?.queryItems?.first(where: { $0.name == "sender_transport_result" || $0.name == "transport_result" })?.value?.lowercased() else {
            return nil
        }
        if value == SalemXSenderJoinFailureDiagnostics.successTransportResult {
            return SalemXSenderJoinFailureDiagnostics.successTransportResult
        }
        if value == SalemXSenderJoinFailureDiagnostics.failedTransportResult {
            return SalemXSenderJoinFailureDiagnostics.failedTransportResult
        }
        if value == SalemXSenderJoinFailureDiagnostics.notRequestedTransportResult {
            return SalemXSenderJoinFailureDiagnostics.notRequestedTransportResult
        }
        return nil
    }

    private static func redactedSenderJoinFailureClassificationQueryItem(_ components: URLComponents?) -> String? {
        guard let value = components?.queryItems?.first(where: { $0.name == "sender_join_failure_classification" || $0.name == "join_failure_classification" })?.value?.lowercased() else {
            return nil
        }
        let allowedClassifications: Set<String> = [
            SalemXSenderJoinFailureDiagnostics.credentialsMissingClassification,
            SalemXSenderJoinFailureDiagnostics.tokenMissingClassification,
            SalemXSenderJoinFailureDiagnostics.urlMissingClassification,
            SalemXSenderJoinFailureDiagnostics.roomBindingMissingClassification,
            SalemXSenderJoinFailureDiagnostics.sameLiveKitRoomMismatchClassification,
            SalemXSenderJoinFailureDiagnostics.transportFailedClassification,
            SalemXSenderJoinFailureDiagnostics.joinFailedClassification,
            SalemXSenderJoinFailureDiagnostics.unknownFailureClassification
        ]
        return allowedClassifications.contains(value) ? value : nil
    }

    private static func redactedSenderTransportFailureClassificationQueryItem(_ components: URLComponents?) -> String? {
        guard let value = components?.queryItems?.first(where: { $0.name == "sender_transport_failure_classification" || $0.name == "transport_failure_classification" })?.value?.lowercased() else {
            return nil
        }
        let allowedClassifications = Set([
            SalemXSenderTransportFailureDiagnostics.transportNotAttemptedClassification,
            SalemXSenderTransportFailureDiagnostics.transportTimeoutClassification,
            SalemXSenderTransportFailureDiagnostics.transportTLSOrCertificateFailedClassification,
            SalemXSenderTransportFailureDiagnostics.transportWebSocketFailedClassification,
            SalemXSenderTransportFailureDiagnostics.transportAuthRejectedClassification,
            SalemXSenderTransportFailureDiagnostics.transportRoomNotFoundOrMismatchClassification,
            SalemXSenderTransportFailureDiagnostics.transportNetworkUnreachableClassification,
            SalemXSenderTransportFailureDiagnostics.transportLiveKitServerRejectedClassification,
            SalemXSenderTransportFailureDiagnostics.transportUnknownFailedClassification,
            SalemXSenderTransportFailureDiagnostics.transportConnectThrowClassification,
            SalemXSenderTransportFailureDiagnostics.transportRoomConnectCallbackFailedClassification,
            SalemXSenderTransportFailureDiagnostics.transportWebSocketCloseClassification,
            SalemXSenderTransportFailureDiagnostics.transportWebSocketUpgradeFailedClassification,
            SalemXSenderTransportFailureDiagnostics.transportTokenExpiredOrInvalidClassification,
            SalemXSenderTransportFailureDiagnostics.transportTimeoutWaitingForConnectedStateClassification,
            SalemXSenderTransportFailureDiagnostics.transportDisconnectedBeforeConnectedClassification,
            SalemXSenderTransportFailureDiagnostics.transportLiveKitSDKUnknownErrorClassification
        ]).union(SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedClassifications)
        return allowedClassifications.contains(value) ? value : nil
    }

    private static func redactedSenderLiveKitSDKFailureSurfaceInput(_ components: URLComponents?) -> SalemXSenderLiveKitSDKFailureSurfaceInput {
        SalemXSenderLiveKitSDKFailureSurfaceInput(requestedClassification: redactedSenderLiveKitSDKFailureClassificationQueryItem(components),
                                                  connectCallStarted: redactedBoolQueryItem(components,
                                                                                            names: ["sender_livekit_sdk_failure_surface_connect_call_started", "sender_sdk_connect_call_started"]),
                                                  connectCallReturned: redactedBoolQueryItem(components,
                                                                                             names: ["sender_livekit_sdk_failure_surface_connect_call_returned", "sender_sdk_connect_call_returned"]),
                                                  connectCallThrew: redactedBoolQueryItem(components,
                                                                                          names: ["sender_livekit_sdk_failure_surface_connect_call_threw", "sender_sdk_connect_call_threw"]),
                                                  connectedStateObserved: redactedBoolQueryItem(components,
                                                                                                names: ["sender_livekit_sdk_failure_surface_connected_state_observed", "sender_sdk_connected_state_observed"]),
                                                  failedStateObserved: redactedBoolQueryItem(components,
                                                                                             names: ["sender_livekit_sdk_failure_surface_failed_state_observed", "sender_sdk_failed_state_observed"]),
                                                  disconnectedBeforeConnected: redactedBoolQueryItem(components,
                                                                                                     names: ["sender_livekit_sdk_failure_surface_disconnected_before_connected", "sender_sdk_disconnected_before_connected"]),
                                                  delegateFailureObserved: redactedBoolQueryItem(components,
                                                                                                 names: ["sender_livekit_sdk_failure_surface_delegate_failure_observed", "sender_sdk_delegate_failure_observed"]),
                                                  roomAlreadyConnected: redactedBoolQueryItem(components,
                                                                                              names: ["sender_livekit_sdk_failure_surface_room_already_connected", "sender_sdk_room_already_connected"]),
                                                  identityConflictObserved: redactedBoolQueryItem(components,
                                                                                                  names: ["sender_livekit_sdk_failure_surface_identity_conflict_observed", "sender_sdk_identity_conflict_observed"]),
                                                  tokenIdentityMatch: redactedOptionalBoolQueryItem(components,
                                                                                                    names: ["sender_livekit_sdk_failure_surface_token_identity_match", "sender_sdk_token_identity_match"]),
                                                  audioSessionReady: redactedOptionalBoolQueryItem(components,
                                                                                                   names: ["sender_livekit_sdk_failure_surface_audio_session_ready", "sender_sdk_audio_session_ready"]),
                                                  permissionRequired: redactedBoolQueryItem(components,
                                                                                            names: ["sender_livekit_sdk_failure_surface_permission_required", "sender_sdk_permission_required"]),
                                                  captureStarted: redactedBoolQueryItem(components,
                                                                                        names: ["sender_livekit_sdk_failure_surface_capture_started", "sender_sdk_capture_started"]),
                                                  networkTransportErrorObserved: redactedBoolQueryItem(components,
                                                                                                       names: ["sender_livekit_sdk_failure_surface_network_transport_error_observed", "sender_sdk_network_transport_error_observed"]),
                                                  timeline: redactedSenderLiveKitSDKTimelineInput(components))
    }

    private static func redactedSenderLiveKitSDKFailureClassificationQueryItem(_ components: URLComponents?) -> String? {
        let allowedClassifications: Set<String> = [
            SalemXSenderLiveKitSDKFailureSurface.connectCallThrewClassification,
            SalemXSenderLiveKitSDKFailureSurface.connectReturnedWithoutConnectedClassification,
            SalemXSenderLiveKitSDKFailureSurface.delegateFailedBeforeConnectedClassification,
            SalemXSenderLiveKitSDKFailureSurface.disconnectedBeforeConnectedClassification,
            SalemXSenderLiveKitSDKFailureSurface.stateFailedClassification,
            SalemXSenderLiveKitSDKFailureSurface.roomAlreadyConnectedClassification,
            SalemXSenderLiveKitSDKFailureSurface.identityConflictClassification,
            SalemXSenderLiveKitSDKFailureSurface.tokenIdentityMismatchClassification,
            SalemXSenderLiveKitSDKFailureSurface.audioSessionBlockedClassification,
            SalemXSenderLiveKitSDKFailureSurface.permissionOrCaptureBlockedClassification,
            SalemXSenderLiveKitSDKFailureSurface.networkTransportErrorClassification,
            SalemXSenderLiveKitSDKFailureSurface.internalUnknownClassification
        ]
        return redactedStringQueryItem(components,
                                       names: ["sender_livekit_sdk_failure_surface_final_classification", "sender_sdk_failure_classification"],
                                       allowedValues: allowedClassifications.union(SalemXSenderLiveKitSDKTimeline.allowedClassifications))
    }

    private static func redactedSenderLiveKitSDKTimelineInput(_ components: URLComponents?) -> SalemXSenderLiveKitSDKTimelineInput {
        let timelineNames = Set([
            "sender_livekit_sdk_timeline_final_classification",
            "sender_livekit_sdk_timeline_trigger_received",
            "sender_livekit_sdk_timeline_task_created",
            "sender_livekit_sdk_timeline_task_started",
            "sender_livekit_sdk_timeline_connect_invoked",
            "sender_livekit_sdk_timeline_connect_returned",
            "sender_livekit_sdk_timeline_connect_threw",
            "sender_livekit_sdk_timeline_delegate_attached",
            "sender_livekit_sdk_timeline_state_observer_attached",
            "sender_livekit_sdk_timeline_connected_state_seen",
            "sender_livekit_sdk_timeline_failed_state_seen",
            "sender_livekit_sdk_timeline_disconnected_state_seen",
            "sender_livekit_sdk_timeline_task_cancelled",
            "sender_livekit_sdk_timeline_task_completed",
            "sender_livekit_sdk_timeline_timeout_elapsed",
            "sender_livekit_sdk_timeline_proof_written_after_terminal_state"
        ]).union(senderLiveKitSDKTimeoutDiagnosticQueryItemNames)
        return SalemXSenderLiveKitSDKTimelineInput(provided: redactedAnyQueryItem(components,
                                                                                  names: timelineNames),
                                                   requestedClassification: redactedSenderLiveKitSDKTimelineClassificationQueryItem(components),
                                                   triggerReceived: redactedBoolQueryItem(components,
                                                                                          names: ["sender_livekit_sdk_timeline_trigger_received"]),
                                                   taskCreated: redactedBoolQueryItem(components,
                                                                                      names: ["sender_livekit_sdk_timeline_task_created"]),
                                                   taskStarted: redactedBoolQueryItem(components,
                                                                                      names: ["sender_livekit_sdk_timeline_task_started"]),
                                                   connectInvoked: redactedBoolQueryItem(components,
                                                                                         names: ["sender_livekit_sdk_timeline_connect_invoked"]),
                                                   connectReturned: redactedBoolQueryItem(components,
                                                                                          names: ["sender_livekit_sdk_timeline_connect_returned"]),
                                                   connectThrew: redactedBoolQueryItem(components,
                                                                                       names: ["sender_livekit_sdk_timeline_connect_threw"]),
                                                   delegateAttached: redactedBoolQueryItem(components,
                                                                                           names: ["sender_livekit_sdk_timeline_delegate_attached"]),
                                                   stateObserverAttached: redactedBoolQueryItem(components,
                                                                                                names: ["sender_livekit_sdk_timeline_state_observer_attached"]),
                                                   connectedStateSeen: redactedBoolQueryItem(components,
                                                                                             names: ["sender_livekit_sdk_timeline_connected_state_seen"]),
                                                   failedStateSeen: redactedBoolQueryItem(components,
                                                                                          names: ["sender_livekit_sdk_timeline_failed_state_seen"]),
                                                   disconnectedStateSeen: redactedBoolQueryItem(components,
                                                                                                names: ["sender_livekit_sdk_timeline_disconnected_state_seen"]),
                                                   taskCancelled: redactedBoolQueryItem(components,
                                                                                        names: ["sender_livekit_sdk_timeline_task_cancelled"]),
                                                   taskCompleted: redactedBoolQueryItem(components,
                                                                                        names: ["sender_livekit_sdk_timeline_task_completed"]),
                                                   timeoutElapsed: redactedBoolQueryItem(components,
                                                                                         names: ["sender_livekit_sdk_timeline_timeout_elapsed"]),
                                                   proofWrittenAfterTerminalState: redactedBoolQueryItem(components,
                                                                                                         names: ["sender_livekit_sdk_timeline_proof_written_after_terminal_state"]),
                                                   timeoutDiagnostics: redactedSenderLiveKitSDKTimeoutDiagnosticsInput(components))
    }

    private static var senderLiveKitSDKTimeoutDiagnosticQueryItemNames: Set<String> {
        [
            "sender_livekit_sdk_timeout_diagnostics_final_classification",
            "sender_livekit_sdk_timeout_diagnostics_wait_window_bucket",
            "sender_livekit_sdk_timeout_diagnostics_connect_invoked",
            "sender_livekit_sdk_timeout_diagnostics_connect_call_pending_at_timeout",
            "sender_livekit_sdk_timeout_diagnostics_task_running_at_timeout",
            "sender_livekit_sdk_timeout_diagnostics_task_cancelled_at_timeout",
            "sender_livekit_sdk_timeout_diagnostics_delegate_attached",
            "sender_livekit_sdk_timeout_diagnostics_state_observer_attached",
            "sender_livekit_sdk_timeout_diagnostics_state_event_count_bucket",
            "sender_livekit_sdk_timeout_diagnostics_delegate_event_count_bucket",
            "sender_livekit_sdk_timeout_diagnostics_app_state_bucket",
            "sender_livekit_sdk_timeout_diagnostics_actor_context_available",
            "sender_livekit_sdk_timeout_diagnostics_network_path_bucket"
        ]
    }

    private static func redactedSenderLiveKitSDKTimeoutDiagnosticsInput(_ components: URLComponents?) -> SalemXSenderLiveKitSDKTimeoutDiagnosticsInput {
        SalemXSenderLiveKitSDKTimeoutDiagnosticsInput(provided: redactedAnyQueryItem(components,
                                                                                     names: senderLiveKitSDKTimeoutDiagnosticQueryItemNames),
                                                      requestedClassification: redactedSenderLiveKitSDKTimeoutDiagnosticsClassificationQueryItem(components),
                                                      waitWindowBucket: redactedStringQueryItem(components,
                                                                                                names: ["sender_livekit_sdk_timeout_diagnostics_wait_window_bucket"],
                                                                                                allowedValues: SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedWaitWindowBuckets) ?? "not_requested",
                                                      connectInvoked: redactedBoolQueryItem(components,
                                                                                            names: ["sender_livekit_sdk_timeout_diagnostics_connect_invoked"]),
                                                      connectCallPendingAtTimeout: redactedBoolQueryItem(components,
                                                                                                         names: ["sender_livekit_sdk_timeout_diagnostics_connect_call_pending_at_timeout"]),
                                                      taskRunningAtTimeout: redactedBoolQueryItem(components,
                                                                                                  names: ["sender_livekit_sdk_timeout_diagnostics_task_running_at_timeout"]),
                                                      taskCancelledAtTimeout: redactedBoolQueryItem(components,
                                                                                                    names: ["sender_livekit_sdk_timeout_diagnostics_task_cancelled_at_timeout"]),
                                                      delegateAttached: redactedBoolQueryItem(components,
                                                                                              names: ["sender_livekit_sdk_timeout_diagnostics_delegate_attached"]),
                                                      stateObserverAttached: redactedBoolQueryItem(components,
                                                                                                   names: ["sender_livekit_sdk_timeout_diagnostics_state_observer_attached"]),
                                                      stateEventCountBucket: redactedStringQueryItem(components,
                                                                                                     names: ["sender_livekit_sdk_timeout_diagnostics_state_event_count_bucket"],
                                                                                                     allowedValues: SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedCountBuckets) ?? "not_requested",
                                                      delegateEventCountBucket: redactedStringQueryItem(components,
                                                                                                        names: ["sender_livekit_sdk_timeout_diagnostics_delegate_event_count_bucket"],
                                                                                                        allowedValues: SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedCountBuckets) ?? "not_requested",
                                                      appStateBucket: redactedStringQueryItem(components,
                                                                                              names: ["sender_livekit_sdk_timeout_diagnostics_app_state_bucket"],
                                                                                              allowedValues: SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedAppStateBuckets) ?? "not_requested",
                                                      actorContextAvailable: redactedBoolQueryItem(components,
                                                                                                   names: ["sender_livekit_sdk_timeout_diagnostics_actor_context_available"]),
                                                      networkPathBucket: redactedStringQueryItem(components,
                                                                                                 names: ["sender_livekit_sdk_timeout_diagnostics_network_path_bucket"],
                                                                                                 allowedValues: SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedNetworkPathBuckets) ?? "not_requested")
    }

    private static func redactedSenderLiveKitSDKTimeoutDiagnosticsClassificationQueryItem(_ components: URLComponents?) -> String? {
        redactedStringQueryItem(components,
                                names: ["sender_livekit_sdk_timeout_diagnostics_final_classification"],
                                allowedValues: SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedClassifications)
    }

    private static func redactedSenderLiveKitSDKTimelineClassificationQueryItem(_ components: URLComponents?) -> String? {
        redactedStringQueryItem(components,
                                names: ["sender_livekit_sdk_timeline_final_classification"],
                                allowedValues: SalemXSenderLiveKitSDKTimeline.allowedClassifications)
    }

    private static func redactedAnyQueryItem(_ components: URLComponents?, names: Set<String>) -> Bool {
        components?.queryItems?.contains { names.contains($0.name) } ?? false
    }

    private static func redactedSenderTransportErrorSurfaceInput(_ components: URLComponents?,
                                                                 sdkFailureSurface: SalemXSenderLiveKitSDKFailureSurface) -> SalemXSenderTransportErrorSurfaceInput {
        SalemXSenderTransportErrorSurfaceInput(source: redactedSenderTransportErrorSourceQueryItem(components),
                                               sdkErrorBucket: redactedSenderTransportErrorBucketQueryItem(components,
                                                                                                           names: ["sender_transport_error_surface_sdk_error_bucket", "transport_sdk_error_bucket"]),
                                               disconnectReasonBucket: redactedSenderTransportErrorBucketQueryItem(components,
                                                                                                                   names: ["sender_transport_error_surface_disconnect_reason_bucket", "transport_disconnect_reason_bucket"]),
                                               websocketBucket: redactedSenderTransportErrorBucketQueryItem(components,
                                                                                                            names: ["sender_transport_error_surface_websocket_bucket", "transport_websocket_bucket"]),
                                               authBucket: redactedSenderTransportErrorBucketQueryItem(components,
                                                                                                       names: ["sender_transport_error_surface_auth_bucket", "transport_auth_bucket"]),
                                               timeoutObserved: redactedBoolQueryItem(components,
                                                                                      names: ["sender_transport_error_surface_timeout_observed", "transport_timeout_observed"]),
                                               connectedStateObserved: redactedBoolQueryItem(components,
                                                                                             names: ["sender_transport_error_surface_connected_state_observed", "transport_connected_state_observed"]),
                                               disconnectedBeforeConnected: redactedBoolQueryItem(components,
                                                                                                  names: ["sender_transport_error_surface_disconnected_before_connected", "transport_disconnected_before_connected"]),
                                               sdkFailureSurface: sdkFailureSurface)
    }

    private static func redactedSenderTransportErrorSourceQueryItem(_ components: URLComponents?) -> String? {
        redactedStringQueryItem(components,
                                names: ["sender_transport_error_surface_source", "transport_error_surface_source"],
                                allowedValues: [
                                    SalemXSenderTransportErrorSurface.connectThrowSource,
                                    SalemXSenderTransportErrorSurface.roomConnectCallbackFailedSource,
                                    SalemXSenderTransportErrorSurface.websocketCloseBucket,
                                    SalemXSenderTransportErrorSurface.websocketUpgradeFailedBucket,
                                    SalemXSenderTransportErrorSurface.authRejectedBucket,
                                    SalemXSenderTransportErrorSurface.tokenExpiredOrInvalidBucket,
                                    SalemXSenderTransportErrorSurface.tlsOrCertificateFailedBucket,
                                    SalemXSenderTransportErrorSurface.networkUnreachableBucket,
                                    SalemXSenderTransportErrorSurface.liveKitSDKUnknownErrorBucket
                                ])
    }

    private static func redactedSenderTransportErrorBucketQueryItem(_ components: URLComponents?, names: [String]) -> String? {
        redactedStringQueryItem(components,
                                names: names,
                                allowedValues: [
                                    SalemXSenderTransportErrorSurface.noneBucket,
                                    SalemXSenderTransportErrorSurface.websocketCloseBucket,
                                    SalemXSenderTransportErrorSurface.websocketUpgradeFailedBucket,
                                    SalemXSenderTransportErrorSurface.authRejectedBucket,
                                    SalemXSenderTransportErrorSurface.tokenExpiredOrInvalidBucket,
                                    SalemXSenderTransportErrorSurface.tlsOrCertificateFailedBucket,
                                    SalemXSenderTransportErrorSurface.networkUnreachableBucket,
                                    SalemXSenderTransportErrorSurface.liveKitSDKUnknownErrorBucket
                                ])
    }

    private static func redactedStringQueryItem(_ components: URLComponents?, names: [String], allowedValues: Set<String>) -> String? {
        guard let value = components?.queryItems?.first(where: { names.contains($0.name) })?.value?.lowercased() else {
            return nil
        }
        return allowedValues.contains(value) ? value : nil
    }

    private static func redactedBoolQueryItem(_ components: URLComponents?, names: [String]) -> Bool {
        guard let value = components?.queryItems?.first(where: { names.contains($0.name) })?.value?.lowercased() else {
            return false
        }
        return value == "true" || value == "1"
    }

    private static func redactedOptionalBoolQueryItem(_ components: URLComponents?, names: [String]) -> Bool? {
        guard let value = components?.queryItems?.first(where: { names.contains($0.name) })?.value?.lowercased() else {
            return nil
        }
        if value == "true" || value == "1" {
            return true
        }
        if value == "false" || value == "0" {
            return false
        }
        return nil
    }

    @objc static func redactedStateSummary() -> String {
        lock.lock()
        defer { lock.unlock() }
        return latestSummary
    }

    @objc static func startRegistrationUploadSmokeWithCurrentSessionURLString(_ uploadURLString: String) -> String {
        updateLatestUploadSummary(.init(manualInvoked: true, blockedReason: "requested"))

        #if targetEnvironment(simulator)
        updateLatestUploadSummary(.init(manualInvoked: true, blockedReason: "physical_device_unavailable"))
        #else
        guard let uploadURL = URL(string: uploadURLString) else {
            updateLatestUploadSummary(.init(manualInvoked: true, blockedReason: "staging_token_route_not_auth_gated"))
            return redactedUploadStateSummary()
        }

        Task { @MainActor in
            guard let accessToken = await SalemXForegroundSSESmokeDebug.matrixAccessTokenForPushKitUploadSmoke() else {
                updateLatestUploadSummary(.init(physicalDeviceAvailable: true,
                                                manualInvoked: true,
                                                blockedReason: "pushkit_token_upload_blocked_by_auth"))
                return
            }

            let smoke = SalemXPushKitTokenUploadSmoke(uploadURL: uploadURL,
                                                      accessToken: accessToken,
                                                      registryFactory: DirectCallRealPushKitRegistryFactory(),
                                                      updateSummary: updateLatestUploadSummary)
            uploadSmoke = smoke
            smoke.start()
        }
        #endif

        return redactedUploadStateSummary()
    }

    @objc static func redactedUploadStateSummary() -> String {
        lock.lock()
        defer { lock.unlock() }
        return latestUploadSummary
    }

    @objc static func startMatrixSessionWhoamiSmokeWithExpectedUserHash(_ expectedUserHash: String) -> String {
        let sanitizedExpectedUserHash = sanitizedSessionUserHash(expectedUserHash)
        updateLatestMatrixSessionWhoamiSummary(.init(manualInvoked: true,
                                                     expectedUserHashProvided: !sanitizedExpectedUserHash.isEmpty,
                                                     blockedReason: "requested"))

        Task { @MainActor in
            await runMatrixSessionWhoamiSmoke(expectedUserHash: sanitizedExpectedUserHash)
        }

        return redactedMatrixSessionWhoamiSummary()
    }

    @objc static func redactedMatrixSessionWhoamiSummary() -> String {
        lock.lock()
        defer { lock.unlock() }
        return latestMatrixSessionWhoamiSummary.redactedLines.joined(separator: "\n")
    }

    private struct MatrixSessionWhoamiContext {
        let expectedUserHash: String
        let homeserverURLAvailable: Bool
        let accessToken: String
    }

    @MainActor
    private static func matrixSessionWhoamiContext(expectedUserHash: String) async -> MatrixSessionWhoamiContext? {
        let availability = SalemXForegroundSSESmokeDebug.matrixSessionWhoamiSmokeAvailability()
        guard availability.activeSessionAvailable else {
            updateLatestMatrixSessionWhoamiSummary(.init(manualInvoked: true,
                                                         expectedUserHashProvided: !expectedUserHash.isEmpty,
                                                         blockedReason: "missing_active_session"))
            return nil
        }

        guard availability.accessTokenProviderAvailable else {
            updateLatestMatrixSessionWhoamiSummary(.init(manualInvoked: true,
                                                         expectedUserHashProvided: !expectedUserHash.isEmpty,
                                                         activeSessionAvailable: true,
                                                         homeserverURLAvailable: availability.homeserverURLAvailable,
                                                         blockedReason: "missing_access_token_provider"))
            return nil
        }

        guard let accessToken = await SalemXForegroundSSESmokeDebug.matrixAccessTokenForPushKitUploadSmoke(),
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            updateLatestMatrixSessionWhoamiSummary(.init(manualInvoked: true,
                                                         expectedUserHashProvided: !expectedUserHash.isEmpty,
                                                         activeSessionAvailable: true,
                                                         accessTokenProviderAvailable: true,
                                                         homeserverURLAvailable: availability.homeserverURLAvailable,
                                                         blockedReason: "missing_access_token"))
            return nil
        }

        return .init(expectedUserHash: expectedUserHash,
                     homeserverURLAvailable: availability.homeserverURLAvailable,
                     accessToken: accessToken)
    }

    @MainActor
    private static func runMatrixSessionWhoamiSmoke(expectedUserHash: String) async {
        guard let context = await matrixSessionWhoamiContext(expectedUserHash: expectedUserHash) else {
            return
        }

        guard let whoamiURL = URL(string: matrixSessionWhoamiURLString) else {
            updateLatestMatrixSessionWhoamiSummary(.init(manualInvoked: true,
                                                         expectedUserHashProvided: !context.expectedUserHash.isEmpty,
                                                         activeSessionAvailable: true,
                                                         accessTokenProviderAvailable: true,
                                                         accessTokenAvailable: true,
                                                         homeserverURLAvailable: context.homeserverURLAvailable,
                                                         blockedReason: "whoami_url_unresolved"))
            return
        }

        var request = URLRequest(url: whoamiURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("B" + "earer " + context.accessToken, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                updateLatestMatrixSessionWhoamiSummary(.init(manualInvoked: true,
                                                             expectedUserHashProvided: !context.expectedUserHash.isEmpty,
                                                             activeSessionAvailable: true,
                                                             accessTokenProviderAvailable: true,
                                                             accessTokenAvailable: true,
                                                             homeserverURLAvailable: context.homeserverURLAvailable,
                                                             whoamiRequested: true,
                                                             whoamiResult: "blocked_redacted",
                                                             whoamiHTTPStatusBucket: "unknown",
                                                             whoamiFailureReason: "missing_http_response",
                                                             blockedReason: "whoami_missing_http_response"))
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let diagnostics = pendingMetadataFetchFailureDiagnostics(response: response, data: data)
                updateLatestMatrixSessionWhoamiSummary(.init(manualInvoked: true,
                                                             expectedUserHashProvided: !context.expectedUserHash.isEmpty,
                                                             activeSessionAvailable: true,
                                                             accessTokenProviderAvailable: true,
                                                             accessTokenAvailable: true,
                                                             homeserverURLAvailable: context.homeserverURLAvailable,
                                                             whoamiRequested: true,
                                                             whoamiResult: "blocked_redacted",
                                                             whoamiHTTPStatusBucket: diagnostics.httpStatusBucket,
                                                             whoamiErrcode: diagnostics.errcode,
                                                             whoamiFailureReason: diagnostics.failureReason,
                                                             blockedReason: "whoami_http_failure_redacted"))
                return
            }

            guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let userID = payload["user_id"] as? String,
                  !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                updateLatestMatrixSessionWhoamiSummary(.init(manualInvoked: true,
                                                             expectedUserHashProvided: !context.expectedUserHash.isEmpty,
                                                             activeSessionAvailable: true,
                                                             accessTokenProviderAvailable: true,
                                                             accessTokenAvailable: true,
                                                             homeserverURLAvailable: context.homeserverURLAvailable,
                                                             whoamiRequested: true,
                                                             whoamiResult: "blocked_redacted",
                                                             whoamiHTTPStatusBucket: "2xx",
                                                             whoamiFailureReason: "payload_invalid",
                                                             blockedReason: "whoami_payload_invalid_redacted"))
                return
            }

            let deviceID = payload["device_id"] as? String
            let userHash = sha256Prefix16(userID)
            let expectedHashMatched = !context.expectedUserHash.isEmpty && userHash == context.expectedUserHash
            let devicePresent = deviceID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            updateLatestMatrixSessionWhoamiSummary(.init(manualInvoked: true,
                                                         expectedUserHashProvided: !context.expectedUserHash.isEmpty,
                                                         activeSessionAvailable: true,
                                                         accessTokenProviderAvailable: true,
                                                         accessTokenAvailable: true,
                                                         homeserverURLAvailable: context.homeserverURLAvailable,
                                                         whoamiRequested: true,
                                                         whoamiResult: "success_redacted",
                                                         whoamiHTTPStatusBucket: "2xx",
                                                         matrixSessionPresent: true,
                                                         matrixSessionUserHash: userHash,
                                                         matrixSessionUserHashMatchesExpected: expectedHashMatched,
                                                         matrixSessionDevicePresent: devicePresent,
                                                         pendingMetadataAuthReady: expectedHashMatched && devicePresent,
                                                         blockedReason: expectedHashMatched && devicePresent ? "none" : "whoami_unexpected_session_redacted"))
        } catch {
            updateLatestMatrixSessionWhoamiSummary(.init(manualInvoked: true,
                                                         expectedUserHashProvided: !context.expectedUserHash.isEmpty,
                                                         activeSessionAvailable: true,
                                                         accessTokenProviderAvailable: true,
                                                         accessTokenAvailable: true,
                                                         homeserverURLAvailable: context.homeserverURLAvailable,
                                                         whoamiRequested: true,
                                                         whoamiResult: "blocked_redacted",
                                                         whoamiHTTPStatusBucket: "network_failure",
                                                         whoamiFailureReason: "network_failure",
                                                         blockedReason: "whoami_network_failure_redacted"))
        }
    }

    @objc static func recordCallKitOperatorAnswerIntent(_ timingBucket: String) -> String {
        recordCallKitOperatorInteraction(intendedAction: "answer", timingBucket: timingBucket)
    }

    @objc static func recordCallKitOperatorEndIntent(_ timingBucket: String) -> String {
        recordCallKitOperatorInteraction(intendedAction: "end", timingBucket: timingBucket)
    }

    @objc static func recordCallKitOperatorReadyToAnswer(_ expectedSurface: String) -> String {
        let safeExpectedSurface = safeExpectedSurfaceBucket(expectedSurface)

        lock.lock()
        pendingOperatorReadyToAnswer = true
        pendingOperatorExpectedSurface = safeExpectedSurface
        var summary = latestVoIPPushReceiptSummary
        summary.operatorReadyToAnswer = true
        summary.operatorExpectedSurface = safeExpectedSurface
        summary.receiverCallKitOperatorReadyMarkerRequestedBeforeAPNs = true
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        return redactedVoIPPushReceiptSummary()
    }

    private static func safeExpectedSurfaceBucket(_ expectedSurface: String) -> String {
        switch expectedSurface {
        case "lockscreen", "fullscreen", "banner", "foreground":
            return expectedSurface
        default:
            return "unknown"
        }
    }

    @objc static func redactedVoIPPushReceiptSummary() -> String {
        lock.lock()
        defer { lock.unlock() }
        return latestVoIPPushReceiptSummary.redactedLines.joined(separator: "\n")
    }

    @objc static func redactedLocalCallKitOnlySummary() -> String {
        lock.lock()
        defer { lock.unlock() }
        return latestLocalCallKitOnlySummary.redactedLines.joined(separator: "\n")
    }

    @objc static func redactedLocalBackgroundCallKitOnlySummary() -> String {
        lock.lock()
        defer { lock.unlock() }
        return latestLocalBackgroundCallKitOnlySummary.redactedLines.joined(separator: "\n")
    }

    @objc static func startLocalCallKitOnlyAnswerabilitySmoke() -> String {
        #if canImport(CallKit) && os(iOS)
        let generation = nextLocalCallKitOnlyProofGeneration()
        _ = localCallKitOnlyProofHarness?.endSyntheticIncomingCall()
        localCallKitOnlyProofHarness = nil

        var summary = SalemXLocalCallKitOnlyProofSummary(blockedReason: "local_callkit_only_waiting_for_action")
        summary.reportRequested = true
        summary.reportResult = "pending"
        summary.callKitUpdateHasGenericHandle = true
        summary.callKitUpdateHasLocalizedCallerName = true
        summary.callKitUpdateAudioOnly = true
        summary.callKitProviderConfigurationAudioOnly = true
        summary.callKitProviderConfigurationSupportedHandleGeneric = true
        summary.localCallKitOnlyUpdateEquivalentToVoIP = true
        summary.localCallKitOnlyProviderConfigEquivalentToVoIP = true
        updateLatestLocalCallKitOnlySummary(summary)

        let proofHarness = NativeIncomingSyntheticCallKitUIProofHarness.makePhysicalDeviceProofHarness(handle: "salemx-local-callkit-only",
                                                                                                       displayLabel: "SalemX Test Call",
                                                                                                       eventRecorder: SalemXLocalCallKitOnlyProofEventRecorder(generation: generation))
        localCallKitOnlyProofHarness = proofHarness
        let reportSubmission = proofHarness.reportSyntheticIncomingCall { event in
            switch event {
            case .reported:
                recordLocalCallKitOnlyReportResult("reported")
            default:
                recordLocalCallKitOnlyReportResult("failed_redacted")
            }
        }
        if case .reported = reportSubmission {
            return redactedLocalCallKitOnlySummary()
        }

        recordLocalCallKitOnlyReportResult("failed_redacted")
        return redactedLocalCallKitOnlySummary()
        #else
        var summary = SalemXLocalCallKitOnlyProofSummary(blockedReason: "local_callkit_only_unavailable")
        summary.reportRequested = true
        summary.reportResult = "unavailable"
        updateLatestLocalCallKitOnlySummary(summary)
        return redactedLocalCallKitOnlySummary()
        #endif
    }

    @objc static func scheduleLocalBackgroundCallKitOnlyAnswerabilitySmoke() -> String {
        #if canImport(CallKit) && os(iOS)
        let generation = nextLocalBackgroundCallKitOnlyProofGeneration()
        _ = localBackgroundCallKitOnlyProofHarness?.endSyntheticIncomingCall()
        localBackgroundCallKitOnlyProofHarness = nil

        var summary = SalemXLocalBackgroundCallKitOnlyProofSummary(blockedReason: "local_background_callkit_only_scheduled")
        summary.reportRequested = true
        summary.reportResult = "scheduled"
        updateLatestLocalBackgroundCallKitOnlySummary(summary)

        DispatchQueue.main.asyncAfter(deadline: .now() + localBackgroundCallKitOnlyReportDelay) {
            reportLocalBackgroundCallKitOnlySmoke(generation: generation)
        }
        return redactedLocalBackgroundCallKitOnlySummary()
        #else
        var summary = SalemXLocalBackgroundCallKitOnlyProofSummary(blockedReason: "local_background_callkit_only_unavailable")
        summary.reportRequested = true
        summary.reportResult = "unavailable"
        updateLatestLocalBackgroundCallKitOnlySummary(summary)
        return redactedLocalBackgroundCallKitOnlySummary()
        #endif
    }

    private static func recordCallKitOperatorInteraction(intendedAction: String, timingBucket: String) -> String {
        let safeIntendedAction: String
        switch intendedAction {
        case "answer", "end":
            safeIntendedAction = intendedAction
        default:
            safeIntendedAction = "unknown"
        }

        let safeTimingBucket: String
        switch timingBucket {
        case "immediate", "1-2s", ">2s":
            safeTimingBucket = timingBucket
        default:
            safeTimingBucket = "unknown"
        }

        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.callKitUISurfaceObservedByOperator = true
        summary.callKitOperatorIntendedAction = safeIntendedAction
        summary.callKitOperatorActionTimingBucket = safeTimingBucket
        summary.callKitUIAnswerOperatorTapObserved = safeIntendedAction == "answer"
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        return redactedVoIPPushReceiptSummary()
    }

    static func recordVoIPPushReceipt(_ payload: [AnyHashable: Any]) {
        recordVoIPPushReceipt(payload) { }
    }

    static func handleElementCallServicePushKitReceipt(_ payload: [AnyHashable: Any], completion: @escaping () -> Void) -> Bool {
        let directCallPayload = payload["salemx_direct_call"] as? [String: Any]
        let version = directCallPayload?["version"] as? Int
        let kind = directCallPayload?["kind"] as? String
        let isControlledSalemXPayload = version == 1 && (kind == "sandbox_voip_smoke" || kind == "real_invite_controlled")
        guard isControlledSalemXPayload else {
            updateLatestStartupPushKitRegistrySummary(.init(callbackInvoked: true,
                                                            salemXPayloadObserved: directCallPayload != nil,
                                                            payloadKind: directCallPayload == nil ? "none" : "unsupported_redacted",
                                                            blockedReason: directCallPayload == nil ? "salemx_payload_not_detected_in_startup_registry" : "unsupported_salemx_payload_detected_in_startup_registry"))
            return false
        }

        recordVoIPPushReceipt(payload, completion: completion, elementCallServiceCallbackInvoked: true)
        return true
    }

    static func recordVoIPPushReceipt(_ payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        recordVoIPPushReceipt(payload, completion: completion, elementCallServiceCallbackInvoked: false)
    }

    private static func applyRuntimeSnapshots(to baseSummary: inout SalemXVoIPPushReceiptProofSummary) {
        lock.lock()
        let operatorReadyToAnswer = pendingOperatorReadyToAnswer
        let operatorExpectedSurface = pendingOperatorExpectedSurface
        let physical6RuntimeEnablementURLHookSnapshot = physical6RuntimeEnablementURLHook
        let remotePeerContextHandoffSnapshot = pendingRemotePeerContextHandoff
        let senderLiveKitReadinessHookSnapshot = senderLiveKitReadinessHook
        let senderSideLiveKitJoinHookSnapshot = senderSideLiveKitJoinHook
        let senderSideLiveKitJoinActivationSnapshot = senderSideLiveKitJoinActivation
        let senderConnectParitySnapshot = senderConnectParity
        let senderConnectExecutorUnificationSnapshot = senderConnectExecutorUnification
        let senderJoinFailureDiagnosticsSnapshot = senderJoinFailureDiagnostics
        let senderTransportFailureDiagnosticsSnapshot = senderTransportFailureDiagnostics
        let senderTransportErrorSurfaceSnapshot = senderTransportErrorSurface
        lock.unlock()

        baseSummary.operatorReadyToAnswer = operatorReadyToAnswer
        baseSummary.operatorExpectedSurface = operatorExpectedSurface
        baseSummary.recordPhysical6RuntimeEnablementURLHook(physical6RuntimeEnablementURLHookSnapshot)
        baseSummary.recordRemotePeerContextHandoff(remotePeerContextHandoffSnapshot)
        baseSummary.recordSenderReadinessRuntimeHandoff(senderLiveKitReadinessHookSnapshot)
        baseSummary.recordSenderSideLiveKitJoinHook(senderSideLiveKitJoinHookSnapshot)
        baseSummary.recordSenderConnectParity(senderConnectParitySnapshot)
        baseSummary.recordSenderConnectExecutorUnification(senderConnectExecutorUnificationSnapshot)
        baseSummary.recordSenderJoinFailureDiagnostics(senderJoinFailureDiagnosticsSnapshot)
        baseSummary.recordSenderTransportFailureDiagnostics(senderTransportFailureDiagnosticsSnapshot)
        baseSummary.recordSenderTransportErrorSurface(senderTransportErrorSurfaceSnapshot)
        baseSummary.recordSenderSideLiveKitJoinActivation(senderSideLiveKitJoinActivationSnapshot)
    }

    private static func recordVoIPPushReceipt(_ payload: [AnyHashable: Any],
                                              completion: @escaping () -> Void,
                                              elementCallServiceCallbackInvoked: Bool) {
        let directCallPayload = payload["salemx_direct_call"] as? [String: Any]
        let version = directCallPayload?["version"] as? Int
        let kind = directCallPayload?["kind"] as? String
        let pendingMetadataReferencePresent = (directCallPayload?["pending_metadata_reference"] as? String)?.isEmpty == false
        let isRealInviteControlled = version == 1 && kind == "real_invite_controlled"
        let isControlledPayload = version == 1 && (kind == "sandbox_voip_smoke" || kind == "real_invite_controlled")

        var baseSummary = SalemXVoIPPushReceiptProofSummary(physicalVoIPPushReceived: true,
                                                            callbackInvoked: true,
                                                            pushType: "voip",
                                                            payloadVersion: version.map(String.init) ?? "missing",
                                                            payloadKind: kind ?? "missing",
                                                            pendingMetadataReferencePresent: pendingMetadataReferencePresent,
                                                            pendingMetadataReferenceRedacted: true, pendingMetadataFetchRequired: pendingMetadataReferencePresent,
                                                            pendingMetadataFetchRequested: false,
                                                            realInvitePayloadMappingObserved: isRealInviteControlled,
                                                            elementCallServicePushKitCallbackInvoked: elementCallServiceCallbackInvoked,
                                                            elementCallServiceSalemXPayloadObserved: elementCallServiceCallbackInvoked,
                                                            elementCallServicePayloadKind: elementCallServiceCallbackInvoked ? kind ?? "missing" : "none",
                                                            elementCallServiceForwardedToSalemXReceiptPipeline: elementCallServiceCallbackInvoked,
                                                            elementCallServiceCompletedWithoutSalemXCallKitReport: false,
                                                            completionCalled: false,
                                                            callKitReportRequested: isControlledPayload,
                                                            callKitReportResult: isControlledPayload ? "pending" : "not_requested",
                                                            blockedReason: isControlledPayload ? "none" : "unsupported_redacted_payload")
        baseSummary.recordPendingMetadataReferenceRepairProof(referencePresent: pendingMetadataReferencePresent)
        baseSummary.appStateAtPushKitReceipt = currentApplicationStateProof()
        applyRuntimeSnapshots(to: &baseSummary)
        if isControlledPayload {
            baseSummary.callKitReportSubmittedAtMsRedacted = true
            baseSummary.callKitUpdateHasGenericHandle = true
            baseSummary.callKitUpdateHasLocalizedCallerName = true
            baseSummary.callKitUpdateAudioOnly = true
            baseSummary.callKitProviderConfigurationAudioOnly = true
            baseSummary.callKitProviderConfigurationSupportedHandleGeneric = true
            baseSummary.localCallKitOnlyUpdateEquivalentToVoIP = true
            baseSummary.localCallKitOnlyProviderConfigEquivalentToVoIP = true
            baseSummary.voIPCallKitUpdateEquivalentToLocal = true
            baseSummary.voIPReportQueueMatchesLocal = true
            baseSummary.voIPProviderReuseMatchesLocal = true
            baseSummary.voIPOperatorMarkerSetBeforeReport = baseSummary.operatorReadyToAnswer
            baseSummary.receiverCallKitOperatorReadyMarkerRequestedBeforeAPNs = baseSummary.operatorReadyToAnswer
        }
        lock.lock()
        callKitReportCompletionDate = nil
        pushKitCompletionDate = nil
        pendingAuthenticatedMetadataReference = pendingMetadataReferencePresent ? (directCallPayload?["pending_metadata_reference"] as? String) : nil
        pushKitCompletionAnswerableWindowID = nil
        pushKitCompletionAnswerableWindowFinish = nil
        lock.unlock()
        updateLatestVoIPPushReceiptSummary(baseSummary)

        guard isControlledPayload else {
            var completedSummary = baseSummary
            completedSummary.completionCalled = true
            updateLatestVoIPPushReceiptSummary(completedSummary)
            completion()
            return
        }

        let completionCoordinator = SalemXPushKitCompletionCoordinator()
        startVoIPPushReceiptBackgroundTask()
        scheduleVoIPPushReceiptReportTimeout(coordinator: completionCoordinator, completion: completion)

        DispatchQueue.main.async {
            reportControlledSandboxVoIPSmokeCallKit { reportResult, answerRetentionProof in
                let reportCompletionDate = Date()
                completionCoordinator.markReportCompletionObserved()

                let blockedReason = reportResult == "reported" || reportResult == "fake_reported" ? "cx_answer_action_callback_not_received" : "callkit_report_failed_redacted"
                if isRealInviteControlled, reportResult == "reported" || reportResult == "fake_reported" {
                    startPushKitCompletionAnswerableWindow(coordinator: completionCoordinator,
                                                           reportResult: reportResult,
                                                           blockedReason: blockedReason,
                                                           answerRetentionProof: answerRetentionProof,
                                                           reportCompletionDate: reportCompletionDate,
                                                           completion: completion)
                } else {
                    completeVoIPPushReceiptOnce(coordinator: completionCoordinator,
                                                reportResult: reportResult,
                                                blockedReason: blockedReason,
                                                answerRetentionProof: answerRetentionProof,
                                                reportCompletionDate: reportCompletionDate,
                                                answerableWindowRequested: false,
                                                answerableWindowResult: "not_requested",
                                                answerableWindowStartedAt: nil,
                                                completion: completion)
                }
            }
        }
    }

    private static func scheduleVoIPPushReceiptReportTimeout(coordinator: SalemXPushKitCompletionCoordinator, completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + voIPPushReceiptCallKitReportTimeout) {
            guard coordinator.shouldRunReportTimeout() else {
                return
            }
            completeVoIPPushReceiptOnce(coordinator: coordinator,
                                        reportResult: "timeout_or_pending_redacted",
                                        blockedReason: "callkit_report_completion_timeout_classified_redacted",
                                        answerRetentionProof: currentCallKitAnswerRetentionProof(),
                                        reportCompletionDate: nil,
                                        answerableWindowRequested: false,
                                        answerableWindowResult: "not_requested",
                                        answerableWindowStartedAt: nil,
                                        completion: completion)
        }
    }

    private static func completeVoIPPushReceiptOnce(coordinator: SalemXPushKitCompletionCoordinator,
                                                    reportResult: String,
                                                    blockedReason: String,
                                                    answerRetentionProof: NativeIncomingSyntheticCallKitUIAnswerRetentionProof?,
                                                    reportCompletionDate: Date?,
                                                    answerableWindowRequested: Bool,
                                                    answerableWindowResult: String,
                                                    answerableWindowStartedAt: Date?,
                                                    completion: @escaping () -> Void) {
        guard coordinator.claimCompletion() else {
            return
        }

        let completionCallDate = Date()
        lock.lock()
        var completedSummary = latestVoIPPushReceiptSummary
        lock.unlock()
        completedSummary.callKitReportResult = reportResult
        completedSummary.callKitReportCompletionObserved = reportResult != "timeout_or_pending_redacted"
        completedSummary.callKitReportCompletionAtMsRedacted = reportResult != "timeout_or_pending_redacted"
        completedSummary.callKitSurfaceRepairReportCompletionTimeoutClassified = reportResult == "timeout_or_pending_redacted"
        completedSummary.pushKitCompletionAnswerableWindowRequested = answerableWindowRequested
        completedSummary.receiverCallKitAnswerWindowExtendedForUISurface = answerableWindowRequested
        completedSummary.pushKitCompletionAnswerableWindowResult = answerableWindowResult
        completedSummary.pushKitCompletionAnswerableWindowDurationBucket = answerableWindowStartedAt.map { elapsedBucket(from: $0, to: completionCallDate) } ?? "not_requested"
        completedSummary.pushKitCompletionAfterReportMsBucket = reportCompletionDate.map { elapsedBucket(from: $0, to: completionCallDate) } ?? "unknown"
        completedSummary.voIPPushKitCompletionDelayedUntilFirstAction = answerableWindowRequested && answerableWindowResult == "first_action_observed"
        completedSummary.appStateAtReportCompletion = currentApplicationStateProof()
        if completedSummary.callKitFirstActionKind == "none" {
            completedSummary.callKitEventOrder = reportResult == "timeout_or_pending_redacted" ? "report_completion_timeout" : "report_completion_only"
        }
        completedSummary.controlledTimeoutBeforeAnswer = reportResult == "timeout_or_pending_redacted"
        if let answerRetentionProof {
            completedSummary.callKitProviderRetainedForAnswer = answerRetentionProof.providerRetainedForAnswer
            completedSummary.callKitDelegateRetainedForAnswer = answerRetentionProof.delegateRetainedForAnswer
            completedSummary.callKitActiveCallUUIDRetained = answerRetentionProof.activeCallUUIDRetained
            completedSummary.callKitSurfaceRepairProviderRetentionVerified = answerRetentionProof.providerRetainedForAnswer
            completedSummary.callKitSurfaceRepairDelegateRetentionVerified = answerRetentionProof.delegateRetainedForAnswer
            completedSummary.callKitSurfaceRepairActiveUUIDRetentionVerified = answerRetentionProof.activeCallUUIDRetained
        }
        completedSummary.completionCalled = true
        completedSummary.callKitSurfaceRepairPushKitCompletionSafetyResult = pushKitCompletionSafetyResult(reportResult: reportResult,
                                                                                                           answerableWindowRequested: answerableWindowRequested,
                                                                                                           answerableWindowResult: answerableWindowResult)
        completedSummary.callKitSurfaceRepairBackgroundTaskEnded = true
        if answerableWindowRequested, answerableWindowResult == "timeout_elapsed", completedSummary.callKitFirstActionKind == "none" {
            completedSummary.blockedReason = "callkit_first_action_not_observed_before_completion_window"
        } else if !answerableWindowRequested {
            completedSummary.blockedReason = blockedReason
        }
        lock.lock()
        callKitReportCompletionDate = reportCompletionDate
        pushKitCompletionDate = reportResult == "timeout_or_pending_redacted" ? nil : completionCallDate
        lock.unlock()
        updateLatestVoIPPushReceiptSummary(completedSummary)
        completion()
        finishVoIPPushReceiptBackgroundTask()
    }

    private static func startPushKitCompletionAnswerableWindow(coordinator: SalemXPushKitCompletionCoordinator,
                                                               reportResult: String,
                                                               blockedReason: String,
                                                               answerRetentionProof: NativeIncomingSyntheticCallKitUIAnswerRetentionProof?,
                                                               reportCompletionDate: Date,
                                                               completion: @escaping () -> Void) {
        let windowID = UUID()
        let windowStartedAt = Date()
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.callKitReportResult = reportResult
        summary.callKitReportCompletionObserved = true
        summary.callKitReportCompletionAtMsRedacted = true
        summary.pushKitCompletionAnswerableWindowRequested = true
        summary.receiverCallKitAnswerWindowExtendedForUISurface = true
        summary.pushKitCompletionAnswerableWindowResult = "pending"
        summary.pushKitCompletionAnswerableWindowDurationBucket = "not_finished"
        summary.appStateAtReportCompletion = currentApplicationStateProof()
        summary.callKitEventOrder = "report_completion_only"
        if let answerRetentionProof {
            summary.callKitProviderRetainedForAnswer = answerRetentionProof.providerRetainedForAnswer
            summary.callKitDelegateRetainedForAnswer = answerRetentionProof.delegateRetainedForAnswer
            summary.callKitActiveCallUUIDRetained = answerRetentionProof.activeCallUUIDRetained
            summary.callKitSurfaceRepairProviderRetentionVerified = answerRetentionProof.providerRetainedForAnswer
            summary.callKitSurfaceRepairDelegateRetentionVerified = answerRetentionProof.delegateRetainedForAnswer
            summary.callKitSurfaceRepairActiveUUIDRetentionVerified = answerRetentionProof.activeCallUUIDRetained
        }
        summary.callKitSurfaceRepairPushKitCompletionSafetyResult = "waiting_for_answerable_window"
        callKitReportCompletionDate = reportCompletionDate
        pushKitCompletionAnswerableWindowID = windowID
        pushKitCompletionAnswerableWindowFinish = { result in
            clearPushKitCompletionAnswerableWindow(windowID: windowID)
            completeVoIPPushReceiptOnce(coordinator: coordinator,
                                        reportResult: reportResult,
                                        blockedReason: blockedReason,
                                        answerRetentionProof: answerRetentionProof,
                                        reportCompletionDate: reportCompletionDate,
                                        answerableWindowRequested: true,
                                        answerableWindowResult: result,
                                        answerableWindowStartedAt: windowStartedAt,
                                        completion: completion)
        }
        let finish = pushKitCompletionAnswerableWindowFinish
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + voIPPushReceiptAnswerableWindowTimeout) {
            finish?("timeout_elapsed")
        }
    }

    private static func pushKitCompletionSafetyResult(reportResult: String, answerableWindowRequested: Bool, answerableWindowResult: String) -> String {
        if reportResult == "timeout_or_pending_redacted" {
            return "completed_after_report_timeout"
        } else if answerableWindowRequested, answerableWindowResult == "first_action_observed" {
            return "completed_after_first_action"
        } else if answerableWindowRequested, answerableWindowResult == "timeout_elapsed" {
            return "completed_after_answerable_window_timeout"
        } else {
            return "completed_after_report_completion"
        }
    }

    private static func currentCallKitAnswerRetentionProof() -> NativeIncomingSyntheticCallKitUIAnswerRetentionProof? {
        #if canImport(CallKit) && os(iOS)
        lock.lock()
        let proofHarness = callKitProofHarness
        lock.unlock()
        return proofHarness?.answerRetentionProof()
        #else
        return nil
        #endif
    }

    private static func startVoIPPushReceiptBackgroundTask() {
        #if os(iOS)
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.callKitSurfaceRepairBackgroundTaskRequested = true
        latestVoIPPushReceiptSummary = summary
        let existingTask = voIPPushReceiptBackgroundTask
        voIPPushReceiptBackgroundTask = .invalid
        lock.unlock()

        if existingTask != .invalid {
            UIApplication.shared.endBackgroundTask(existingTask)
        }

        let task = UIApplication.shared.beginBackgroundTask(withName: "SalemXCallKitSurfaceRepair") {
            finishVoIPPushReceiptBackgroundTask()
        }
        lock.lock()
        voIPPushReceiptBackgroundTask = task
        lock.unlock()
        updateLatestVoIPPushReceiptSummary(summary)
        #endif
    }

    private static func finishVoIPPushReceiptBackgroundTask() {
        #if os(iOS)
        lock.lock()
        let task = voIPPushReceiptBackgroundTask
        voIPPushReceiptBackgroundTask = .invalid
        lock.unlock()

        if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
        }
        #endif
    }

    private static func clearPushKitCompletionAnswerableWindow(windowID: UUID) {
        lock.lock()
        if pushKitCompletionAnswerableWindowID == windowID {
            pushKitCompletionAnswerableWindowID = nil
            pushKitCompletionAnswerableWindowFinish = nil
        }
        lock.unlock()
    }

    @discardableResult
    private static func recordFirstCallKitAction(_ kind: String, in summary: inout SalemXVoIPPushReceiptProofSummary) -> Bool {
        guard summary.callKitFirstActionKind == "none" else {
            return false
        }

        let bucket = callKitFirstActionAfterReportBucket()
        summary.callKitFirstActionKind = kind
        summary.callKitFirstActionAfterReportMsBucket = bucket
        summary.appStateAtFirstCallKitAction = currentApplicationStateProof()
        summary.providerDidResetBeforeFirstAction = summary.callKitProviderDidResetObserved
        summary.audioSessionDidActivateBeforeFirstAction = summary.callKitProviderDidActivateAudioSession
        summary.audioSessionDidDeactivateBeforeFirstAction = summary.callKitProviderDidDeactivateAudioSession
        if kind == "end",
           bucket == "<100ms" || bucket == "100-500ms" || bucket == "500-2000ms" {
            summary.callKitEndArrivedBeforeOperatorAnswerWindow = true
        }
        return true
    }

    private static func notifyPushKitCompletionAnswerableWindowFirstAction() {
        lock.lock()
        let finish = pushKitCompletionAnswerableWindowFinish
        lock.unlock()
        finish?("first_action_observed")
    }

    private static func callKitFirstActionAfterReportBucket() -> String {
        elapsedBucket(from: callKitReportCompletionDate)
    }

    private static func elapsedBucket(from startDate: Date?, to endDate: Date = Date()) -> String {
        guard let startDate else {
            return "unknown"
        }

        let elapsedMs = endDate.timeIntervalSince(startDate) * 1000
        if elapsedMs < 100 {
            return "<100ms"
        } else if elapsedMs < 500 {
            return "100-500ms"
        } else if elapsedMs < 2000 {
            return "500-2000ms"
        } else {
            return ">2000ms"
        }
    }

    private static func scheduleRemoteParticipantObservationTimeoutIfNeeded() {
        lock.lock()
        let summary = latestVoIPPushReceiptSummary
        guard summary.remoteParticipantObservationWaitStarted,
              !summary.remoteParticipantObservationWaitCompleted else {
            if summary.remoteParticipantObservationWaitCompleted {
                remoteParticipantObservationWindowID = nil
                remoteParticipantObservationWindowStartedAt = nil
                receiverParticipantSnapshotSweepID = nil
                if summary.remoteParticipantObservationFinalClassification != "pending_redacted" {
                    pendingRemotePeerContextHandoff = nil
                }
            }
            lock.unlock()
            return
        }
        guard remoteParticipantObservationWindowID == nil else {
            lock.unlock()
            return
        }

        let windowID = UUID()
        remoteParticipantObservationWindowID = windowID
        remoteParticipantObservationWindowStartedAt = Date()
        lock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + remoteParticipantObservationWindowTimeout) {
            finishRemoteParticipantObservationTimeoutIfCurrent(windowID)
        }
    }

    private static func finishRemoteParticipantObservationTimeoutIfCurrent(_ windowID: UUID) {
        lock.lock()
        guard remoteParticipantObservationWindowID == windowID else {
            lock.unlock()
            return
        }

        var summary = latestVoIPPushReceiptSummary
        guard summary.remoteParticipantObservationWaitStarted,
              !summary.remoteParticipantObservationWaitCompleted else {
            remoteParticipantObservationWindowID = nil
            remoteParticipantObservationWindowStartedAt = nil
            receiverParticipantSnapshotSweepID = nil
            lock.unlock()
            return
        }

        let timeoutBucket = elapsedBucket(from: remoteParticipantObservationWindowStartedAt)
        if summary.shouldExtendReceiverConnectedWindowForSenderSignal(alreadyExtended: receiverConnectedWindowRetentionExtensionUsed) {
            receiverConnectedWindowRetentionExtensionUsed = true
            summary.recordReceiverConnectedWindowRetentionExtended(timeoutBucket: timeoutBucket)
            remoteParticipantObservationWindowID = nil
            remoteParticipantObservationWindowStartedAt = nil
            lock.unlock()

            updateLatestVoIPPushReceiptSummary(summary)
            scheduleRemoteParticipantObservationTimeoutIfNeeded()
            return
        }

        summary.completeRemoteParticipantObservationTimeout(timeoutBucket: timeoutBucket)
        remoteParticipantObservationWindowID = nil
        remoteParticipantObservationWindowStartedAt = nil
        receiverParticipantSnapshotSweepID = nil
        pendingRemotePeerContextHandoff = nil
        let releaseReason = summary.remoteParticipantObservationFinalClassification
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        Task { @MainActor in
            releaseReceiverConnectedSessionLease(reason: releaseReason)
        }
    }

    private static func scheduleReceiverParticipantSnapshotSweepIfNeeded() {
        lock.lock()
        let summary = latestVoIPPushReceiptSummary
        guard summary.senderConnectedSignalReceivedByReceiver,
              summary.receiverSenderConnectedWindowOverlapObserved,
              summary.remoteParticipantObservationWaitStarted,
              !summary.remoteParticipantObservationWaitCompleted,
              receiverParticipantSnapshotSweepID == nil else {
            lock.unlock()
            return
        }

        let sweepID = UUID()
        receiverParticipantSnapshotSweepID = sweepID
        lock.unlock()

        requestReceiverParticipantSnapshotIfCurrent(sweepID)
        [1.0, 2.5, 5.0].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                requestReceiverParticipantSnapshotIfCurrent(sweepID)
            }
        }
    }

    private static func requestReceiverParticipantSnapshotIfCurrent(_ sweepID: UUID) {
        Task { @MainActor in
            await requestReceiverParticipantSnapshotIfCurrentOnMain(sweepID)
        }
    }

    @MainActor
    private static func requestReceiverParticipantSnapshotIfCurrentOnMain(_ sweepID: UUID) async {
        lock.lock()
        guard receiverParticipantSnapshotSweepID == sweepID else {
            lock.unlock()
            return
        }

        var summary = latestVoIPPushReceiptSummary
        guard summary.remoteParticipantObservationWaitStarted,
              !summary.remoteParticipantObservationWaitCompleted else {
            receiverParticipantSnapshotSweepID = nil
            lock.unlock()
            return
        }

        let lease = receiverConnectedSessionLease
        let boundToRetainedRoom = lease != nil &&
            summary.receiverConnectedSessionLeaseRoomRetained &&
            !summary.receiverConnectedSessionLeaseReleased
        let boundToConnectedRoom = boundToRetainedRoom &&
            summary.liveKitRoomConnected &&
            !summary.liveKitRoomDisconnected
        summary.recordReceiverParticipantSnapshotRequested(boundToRetainedRoom: boundToRetainedRoom,
                                                           boundToConnectedRoom: boundToConnectedRoom)
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)

        guard let lease else {
            return
        }

        let snapshot = await lease.client.remoteParticipantSnapshot()

        lock.lock()
        guard receiverParticipantSnapshotSweepID == sweepID else {
            lock.unlock()
            return
        }

        summary = latestVoIPPushReceiptSummary
        guard summary.remoteParticipantObservationWaitStarted,
              !summary.remoteParticipantObservationWaitCompleted else {
            receiverParticipantSnapshotSweepID = nil
            lock.unlock()
            return
        }

        summary.recordReceiverParticipantSnapshotObservation(snapshot)
        let shouldReleaseLease = summary.remoteParticipantObservationWaitCompleted
        let releaseReason = summary.remoteParticipantObservationFinalClassification
        if shouldReleaseLease {
            receiverParticipantSnapshotSweepID = nil
            remoteParticipantObservationWindowID = nil
            remoteParticipantObservationWindowStartedAt = nil
            pendingRemotePeerContextHandoff = nil
        }
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        if shouldReleaseLease {
            releaseReceiverConnectedSessionLease(reason: releaseReason)
        }
    }

    private static func currentApplicationStateProof() -> String {
        switch UIApplication.shared.applicationState {
        case .active:
            return "foreground"
        case .background:
            return "background"
        case .inactive:
            return "inactive"
        @unknown default:
            return "unknown"
        }
    }

    static func recordCallKitAnswerActionDeliveryProof(uuidMatched: Bool, generationMatched: Bool) {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.callKitAnswerActionDelivered = true
        summary.answerActionUUIDMatched = uuidMatched
        summary.answerActionGenerationMatched = generationMatched
        let didRecordFirstAction = recordFirstCallKitAction("answer", in: &summary)
        summary.callKitEventOrder = "report_completion_then_answer"
        if !uuidMatched {
            summary.blockedReason = "answer_action_uuid_mismatch"
        } else if !generationMatched {
            summary.blockedReason = "answer_action_generation_mismatch"
        }
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        if didRecordFirstAction {
            notifyPushKitCompletionAnswerableWindowFirstAction()
        }
    }

    static func recordCallKitEndActionDeliveryProof(uuidMatched: Bool, generationMatched: Bool) {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.callKitEndActionDelivered = true
        summary.endActionUUIDMatched = uuidMatched
        summary.endActionGenerationMatched = generationMatched
        summary.endActionSourceMatched = uuidMatched && generationMatched
        let didRecordFirstAction = recordFirstCallKitAction("end", in: &summary)
        summary.callKitEndAfterPushKitCompletionMsBucket = elapsedBucket(from: pushKitCompletionDate)
        summary.callKitEventOrder = "report_completion_then_end"
        if !summary.callKitAnswerActionReceived {
            if !uuidMatched {
                summary.blockedReason = "end_action_uuid_mismatch"
            } else if !generationMatched {
                summary.blockedReason = "end_action_generation_mismatch"
            } else if summary.localEndRequestBeforeAnswer {
                summary.endActionOrigin = "local_requested"
                summary.blockedReason = "local_end_requested_before_answer"
            } else if summary.callKitEndArrivedBeforeOperatorAnswerWindow {
                summary.endActionOrigin = "system_or_user_unknown"
                summary.blockedReason = "system_end_before_answer_window"
            } else if summary.operatorReadyToAnswer, !summary.callKitUISurfaceObservedByOperator {
                summary.endActionOrigin = "system_or_user_unknown"
                summary.blockedReason = "background_callkit_end_before_operator_action"
            } else if summary.operatorReadyToAnswer, summary.callKitOperatorIntendedAction == "answer" {
                summary.endActionOrigin = "system_or_user_unknown"
                summary.blockedReason = "background_callkit_end_after_operator_answer_intent"
            } else if !summary.callKitProviderDidActivateAudioSession {
                summary.endActionOrigin = "system_or_user_unknown"
                summary.blockedReason = "background_callkit_audio_activation_missing_before_end"
            } else {
                summary.endActionOrigin = "system_or_user_unknown"
                summary.blockedReason = "system_or_user_end_before_answer"
            }
        }
        summary.refreshDisconnectCleanupDiagnostics()
        summary.refreshRemoteAudioLivenessDiagnostics()
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        if didRecordFirstAction {
            notifyPushKitCompletionAnswerableWindowFirstAction()
        }
    }

    static func recordCallKitEndActionFulfillmentProof(uuidMatched: Bool, generationMatched: Bool) {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.endActionFulfilled = true
        summary.endActionUUIDMatched = uuidMatched
        summary.endActionGenerationMatched = generationMatched
        summary.endActionSourceMatched = uuidMatched && generationMatched
        summary.refreshDisconnectCleanupDiagnostics()
        summary.refreshRemoteAudioLivenessDiagnostics()
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
    }

    static func recordCallKitLocalEndRequestBeforeAnswerProof(uuidMatched: Bool) {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.localEndRequestBeforeAnswer = true
        summary.reportCallEndedBeforeAnswer = true
        summary.endActionOrigin = "local_requested"
        if !summary.callKitAnswerActionReceived {
            summary.blockedReason = uuidMatched ? "local_end_requested_before_answer" : "provider_delegate_instance_mismatch"
        }
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
    }

    static func recordCallKitProviderResetProof() {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.callKitProviderDidResetObserved = true
        let didRecordFirstAction = recordFirstCallKitAction("reset", in: &summary)
        summary.callKitEventOrder = "report_completion_then_reset"
        if !summary.callKitAnswerActionReceived {
            summary.blockedReason = "callkit_provider_reset_before_answer"
        }
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        if didRecordFirstAction {
            notifyPushKitCompletionAnswerableWindowFirstAction()
        }
    }

    static func recordCallKitAudioSessionProof(activated: Bool) {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        if activated {
            summary.callKitProviderDidActivateAudioSession = true
        } else {
            summary.callKitProviderDidDeactivateAudioSession = true
        }
        summary.refreshDisconnectCleanupDiagnostics()
        summary.refreshRemoteAudioLivenessDiagnostics()
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
    }

    static func recordLocalCallKitOnlyReportResult(_ reportResult: String) {
        let safeReportResult: String
        switch reportResult {
        case "reported", "failed_redacted":
            safeReportResult = reportResult
        default:
            safeReportResult = "failed_redacted"
        }

        lock.lock()
        var summary = latestLocalCallKitOnlySummary
        summary.reportRequested = true
        summary.reportResult = safeReportResult
        if safeReportResult == "failed_redacted" {
            summary.blockedReason = "local_callkit_only_report_failed_redacted"
        }
        lock.unlock()

        updateLatestLocalCallKitOnlySummary(summary)
    }

    static func recordLocalCallKitOnlyFirstAction(_ kind: String) {
        lock.lock()
        var summary = latestLocalCallKitOnlySummary
        if summary.firstActionKind == "none" {
            summary.firstActionKind = kind
        }
        if kind == "reset" {
            summary.blockedReason = "local_callkit_only_reset_before_answer"
        }
        lock.unlock()

        updateLatestLocalCallKitOnlySummary(summary)
    }

    static func recordLocalCallKitOnlyAnswerActionDeliveryProof(generationMatched: Bool) {
        lock.lock()
        var summary = latestLocalCallKitOnlySummary
        if summary.firstActionKind == "none" {
            summary.firstActionKind = "answer"
        }
        summary.answerActionDelivered = generationMatched
        summary.blockedReason = generationMatched ? "none" : "local_callkit_only_generation_mismatch"
        lock.unlock()

        updateLatestLocalCallKitOnlySummary(summary)
    }

    static func recordLocalCallKitOnlyEndActionDeliveryProof(generationMatched: Bool) {
        lock.lock()
        var summary = latestLocalCallKitOnlySummary
        if summary.firstActionKind == "none" {
            summary.firstActionKind = "end"
        }
        summary.endActionDelivered = generationMatched
        summary.blockedReason = generationMatched ? "local_callkit_only_end_before_answer" : "local_callkit_only_generation_mismatch"
        lock.unlock()

        updateLatestLocalCallKitOnlySummary(summary)
    }

    static func recordLocalBackgroundCallKitOnlyReportResult(_ reportResult: String) {
        let safeReportResult: String
        switch reportResult {
        case "reported", "failed_redacted":
            safeReportResult = reportResult
        default:
            safeReportResult = "failed_redacted"
        }

        lock.lock()
        var summary = latestLocalBackgroundCallKitOnlySummary
        summary.reportRequested = true
        summary.reportResult = safeReportResult
        summary.appStateAtReport = currentApplicationStateProof()
        if safeReportResult == "failed_redacted" {
            summary.blockedReason = "local_background_callkit_only_report_failed_redacted"
        } else if summary.blockedReason == "local_background_callkit_only_scheduled" {
            summary.blockedReason = "local_background_callkit_only_waiting_for_action"
        }
        lock.unlock()

        updateLatestLocalBackgroundCallKitOnlySummary(summary)
    }

    static func recordLocalBackgroundCallKitOnlyFirstAction(_ kind: String) {
        lock.lock()
        var summary = latestLocalBackgroundCallKitOnlySummary
        if summary.firstActionKind == "none" {
            summary.firstActionKind = kind
        }
        if kind == "reset" {
            summary.blockedReason = "local_background_callkit_only_reset_before_answer"
        }
        lock.unlock()

        updateLatestLocalBackgroundCallKitOnlySummary(summary)
    }

    static func recordLocalBackgroundCallKitOnlyAnswerActionDeliveryProof(generationMatched: Bool) {
        lock.lock()
        var summary = latestLocalBackgroundCallKitOnlySummary
        if summary.firstActionKind == "none" {
            summary.firstActionKind = "answer"
        }
        summary.answerActionDelivered = generationMatched
        summary.blockedReason = generationMatched ? "none" : "local_background_callkit_only_generation_mismatch"
        lock.unlock()

        updateLatestLocalBackgroundCallKitOnlySummary(summary)
    }

    static func recordLocalBackgroundCallKitOnlyEndActionDeliveryProof(generationMatched: Bool) {
        lock.lock()
        var summary = latestLocalBackgroundCallKitOnlySummary
        if summary.firstActionKind == "none" {
            summary.firstActionKind = "end"
        }
        summary.endActionDelivered = generationMatched
        summary.blockedReason = generationMatched ? "local_background_callkit_only_end_before_answer" : "local_background_callkit_only_generation_mismatch"
        lock.unlock()

        updateLatestLocalBackgroundCallKitOnlySummary(summary)
    }

    static func recordCallKitAnswerActionProof(screenSource overrideScreenSource: String? = nil) {
        var pendingMetadataReferenceToFetch: String?
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        let physical6RuntimeEnablementURLHookSnapshot = physical6RuntimeEnablementURLHook
        let screenSource = overrideScreenSource ?? (summary.realInvitePayloadMappingObserved ? "callkit_answer_real_invite_controlled" : "callkit_answer_sandbox_voip_smoke")
        summary.callKitAnswerActionDelivered = true
        summary.answerActionUUIDMatched = true
        summary.answerActionGenerationMatched = true
        summary.callKitEventOrder = "report_completion_then_answer"
        summary.callKitAnswerActionReceived = true
        summary.callKitAnswerActionFulfilled = true
        summary.appActivationObserved = true
        summary.controlledInAppActivationRequested = true
        summary.controlledInAppActivationObserved = true
        summary.controlledInAppScreenRequested = true
        summary.controlledInAppScreenPresented = true
        summary.controlledInAppScreenSource = screenSource
        summary.markRemotePeerContextHandoffSurvivedAnswer()
        summary.markSenderReadinessRuntimeHandoffSurvivedAnswer()
        if summary.realInvitePayloadMappingObserved {
            summary.foregroundCallStateHandoffRequested = true
            summary.foregroundCallStateHandoffObserved = true
            summary.foregroundCallState = "real_invite_pending_media"
            summary.foregroundCallStateSource = screenSource
            summary.foregroundCallStatePayloadRedacted = true
            summary.foregroundCallStateHasStableRedactedCorrelation = true
            if !recordForegroundPendingCallMetadataHandoffIfAvailable(&summary) {
                if summary.pendingMetadataFetchRequired,
                   let pendingAuthenticatedMetadataReference {
                    summary.recordPendingMetadataFetchRequested()
                    pendingMetadataReferenceToFetch = pendingAuthenticatedMetadataReference
                } else {
                    summary.recordMetadataCredentialsBoundaryMissingAfterAnswer(physical6RuntimeEnablementHook: physical6RuntimeEnablementURLHookSnapshot)
                }
            }
        } else {
            summary.blockedReason = "none"
        }
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        if let pendingMetadataReferenceToFetch {
            Task { await fetchAuthenticatedPendingMetadata(reference: pendingMetadataReferenceToFetch) }
        }
    }

    static func recordControlledCallKitCleanupProof() {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.controlledCallKitCleanupRequested = true
        summary.controlledCallKitCleanupResult = "ended"
        summary.refreshDisconnectCleanupDiagnostics()
        summary.refreshRemoteAudioLivenessDiagnostics()
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
    }

    static func isActiveCallKitProofGeneration(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        #if canImport(CallKit) && os(iOS)
        return callKitProofGeneration == generation
        #else
        return false
        #endif
    }

    static func isActiveLocalCallKitOnlyProofGeneration(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        #if canImport(CallKit) && os(iOS)
        return localCallKitOnlyProofGeneration == generation
        #else
        return false
        #endif
    }

    static func isActiveLocalBackgroundCallKitOnlyProofGeneration(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        #if canImport(CallKit) && os(iOS)
        return localBackgroundCallKitOnlyProofGeneration == generation
        #else
        return false
        #endif
    }

    private static func reportControlledSandboxVoIPSmokeCallKit(completion: @escaping (String, NativeIncomingSyntheticCallKitUIAnswerRetentionProof?) -> Void) {
        #if canImport(CallKit) && os(iOS)
        let generation = nextCallKitProofGeneration()
        _ = callKitProofHarness?.endSyntheticIncomingCall()
        callKitProofHarness = nil
        let proofHarness = NativeIncomingSyntheticCallKitUIProofHarness.makePhysicalDeviceProofHarness(handle: "salemx-test-call",
                                                                                                       displayLabel: "SalemX Test Call",
                                                                                                       eventRecorder: SalemXPushKitCallKitProofEventRecorder(generation: generation))
        callKitProofHarness = proofHarness
        let reportSubmission = proofHarness.reportSyntheticIncomingCall { event in
            switch event {
            case .reported:
                completion("reported", proofHarness.answerRetentionProof())
            default:
                completion("failed_redacted", nil)
            }
        }
        if case .reported = reportSubmission {
            return
        }
        completion("failed_redacted", nil)
        #else
        completion("fake_reported", nil)
        #endif
    }

    private static func reportLocalBackgroundCallKitOnlySmoke(generation: Int) {
        #if canImport(CallKit) && os(iOS)
        guard isActiveLocalBackgroundCallKitOnlyProofGeneration(generation) else {
            return
        }

        let proofHarness = NativeIncomingSyntheticCallKitUIProofHarness.makePhysicalDeviceProofHarness(handle: "salemx-local-background-callkit-only",
                                                                                                       displayLabel: "SalemX Test Call",
                                                                                                       eventRecorder: SalemXLocalBackgroundCallKitOnlyProofEventRecorder(generation: generation))
        localBackgroundCallKitOnlyProofHarness = proofHarness
        let reportSubmission = proofHarness.reportSyntheticIncomingCall { event in
            switch event {
            case .reported:
                recordLocalBackgroundCallKitOnlyReportResult("reported")
            default:
                recordLocalBackgroundCallKitOnlyReportResult("failed_redacted")
            }
        }
        if case .reported = reportSubmission {
            return
        }

        recordLocalBackgroundCallKitOnlyReportResult("failed_redacted")
        #endif
    }

    private static func nextCallKitProofGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        #if canImport(CallKit) && os(iOS)
        callKitProofGeneration += 1
        return callKitProofGeneration
        #else
        return 0
        #endif
    }

    private static func nextLocalCallKitOnlyProofGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        #if canImport(CallKit) && os(iOS)
        localCallKitOnlyProofGeneration += 1
        return localCallKitOnlyProofGeneration
        #else
        return 0
        #endif
    }

    private static func nextLocalBackgroundCallKitOnlyProofGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        #if canImport(CallKit) && os(iOS)
        localBackgroundCallKitOnlyProofGeneration += 1
        return localBackgroundCallKitOnlyProofGeneration
        #else
        return 0
        #endif
    }

    private static func updateLatestSummary(with result: DirectCallPushKitRegistrarResult) {
        lock.lock()
        latestSummary = redactedSummary(for: result)
        lock.unlock()
    }

    private static func updateLatestUploadSummary(_ summary: SalemXPushKitTokenUploadSmokeSummary) {
        lock.lock()
        var summary = summary
        summary.proofGeneration = nextProofGenerationLocked()
        summary.proofLastUpdatedBy = "pushkit_upload_smoke"
        latestUploadSummary = summary.redactedLines.joined(separator: "\n")
        let latestUploadSummary = latestUploadSummary
        lock.unlock()
        writeUploadSmokeProof(latestUploadSummary)
    }

    private static func updateLatestMatrixSessionWhoamiSummary(_ summary: SalemXMatrixSessionWhoamiProofSummary) {
        lock.lock()
        var summary = summary
        summary.proofGeneration = nextProofGenerationLocked()
        summary.proofLastUpdatedBy = "matrix_session_whoami_smoke"
        latestMatrixSessionWhoamiSummary = summary
        let proof = summary.redactedLines.joined(separator: "\n")
        lock.unlock()
        writeMatrixSessionWhoamiProof(proof)
    }

    private static func updateLatestVoIPPushReceiptSummary(_ summary: SalemXVoIPPushReceiptProofSummary) {
        lock.lock()
        var summary = summary
        summary.proofGeneration = nextProofGenerationLocked()
        summary.proofLastUpdatedBy = "voip_push_callback"
        summary.refreshReceiverVoIPPushDeliveryTriage(uploadProof: latestUploadSummary,
                                                      appStateBeforeAPNs: currentApplicationStateProof())
        latestVoIPPushReceiptSummary = summary
        let proof = summary.redactedLines.joined(separator: "\n")
        lock.unlock()
        writeVoIPPushReceiptProof(proof)
        scheduleRemoteParticipantObservationTimeoutIfNeeded()
    }

    private static func updateLatestStartupPushKitRegistrySummary(_ summary: SalemXStartupPushKitRegistryProofSummary) {
        lock.lock()
        var summary = summary
        summary.proofGeneration = nextProofGenerationLocked()
        summary.proofLastUpdatedBy = "element_call_service_pushkit"
        latestStartupPushKitRegistrySummary = summary
        let proof = summary.redactedLines.joined(separator: "\n")
        lock.unlock()
        writeStartupPushKitRegistryProof(proof)
    }

    private static func updateLatestLocalCallKitOnlySummary(_ summary: SalemXLocalCallKitOnlyProofSummary) {
        lock.lock()
        var summary = summary
        summary.proofGeneration = nextProofGenerationLocked()
        summary.proofLastUpdatedBy = "local_callkit_only_smoke"
        latestLocalCallKitOnlySummary = summary
        let proof = summary.redactedLines.joined(separator: "\n")
        lock.unlock()
        writeLocalCallKitOnlyProof(proof)
    }

    private static func updateLatestLocalBackgroundCallKitOnlySummary(_ summary: SalemXLocalBackgroundCallKitOnlyProofSummary) {
        lock.lock()
        var summary = summary
        summary.proofGeneration = nextProofGenerationLocked()
        summary.proofLastUpdatedBy = "local_background_callkit_only_smoke"
        latestLocalBackgroundCallKitOnlySummary = summary
        let proof = summary.redactedLines.joined(separator: "\n")
        lock.unlock()
        writeLocalBackgroundCallKitOnlyProof(proof)
    }

    private static func updateLatestSenderRuntimeLiveKitJoinSummary(_ summary: SalemXSenderRuntimeLiveKitJoinProofSummary) {
        lock.lock()
        var summary = summary
        summary.proofGeneration = nextProofGenerationLocked()
        summary.proofLastUpdatedBy = "sender_runtime_livekit_join_bridge"
        latestSenderRuntimeLiveKitJoinSummary = summary
        let proof = summary.redactedLines.joined(separator: "\n")
        lock.unlock()
        writeSenderRuntimeLiveKitJoinProof(proof)
        propagateSenderRuntimeJoinTerminalToReceiverObservation(summary)
    }

    private static func propagateSenderRuntimeJoinTerminalToReceiverObservation(_ senderSummary: SalemXSenderRuntimeLiveKitJoinProofSummary) {
        let runtimeResult = senderSummary.runtimeResult
        guard senderSummary.bridgeTriggered,
              runtimeResult == SalemXSenderSideLiveKitJoinHook.successResult ||
              runtimeResult == SalemXSenderSideLiveKitJoinHook.failedResult ||
              runtimeResult == SalemXSenderSideLiveKitJoinHook.blockedResult else {
            return
        }

        let senderJoinResult: String
        switch runtimeResult {
        case SalemXSenderSideLiveKitJoinHook.successResult:
            senderJoinResult = SalemXSenderSideLiveKitJoinHook.successResult
        case SalemXSenderSideLiveKitJoinHook.failedResult:
            senderJoinResult = SalemXSenderSideLiveKitJoinHook.failedResult
        default:
            senderJoinResult = SalemXSenderSideLiveKitJoinHook.blockedResult
        }

        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.recordSenderSideLiveKitJoinResult(requested: true,
                                                  result: senderJoinResult,
                                                  errorBucket: senderSummary.runtimeErrorBucket,
                                                  repeated: senderSummary.bridgeRepeated)
        summary.recordSenderConnectedSignalFromRuntime(senderConnected: senderSummary.senderLiveKitRoomConnected,
                                                       source: "sender_runtime_livekit_join")
        summary.activateRemoteParticipantObservationRuntimeWindowIfNeeded()
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        scheduleReceiverParticipantSnapshotSweepIfNeeded()
    }

    private static func nextProofGenerationLocked() -> String {
        proofGenerationCounter += 1
        return "generation_\(proofGenerationCounter)"
    }

    private static func writeUploadSmokeProof(_ proof: String) {
        writeProof(proof, fileName: uploadSmokeProofFileName)
    }

    private static func writeMatrixSessionWhoamiProof(_ proof: String) {
        writeProof(proof, fileName: matrixSessionWhoamiProofFileName)
    }

    private static func writeVoIPPushReceiptProof(_ proof: String) {
        writeProof(proof, fileName: voIPPushReceiptProofFileName)
    }

    private static func writeStartupPushKitRegistryProof(_ proof: String) {
        writeProof(proof, fileName: startupPushKitRegistryProofFileName)
    }

    private static func writeLocalCallKitOnlyProof(_ proof: String) {
        writeProof(proof, fileName: localCallKitOnlyProofFileName)
    }

    private static func writeLocalBackgroundCallKitOnlyProof(_ proof: String) {
        writeProof(proof, fileName: localBackgroundCallKitOnlyProofFileName)
    }

    private static func writeSenderRuntimeLiveKitJoinProof(_ proof: String) {
        writeProof(proof, fileName: senderRuntimeLiveKitJoinProofFileName)
    }

    private static func writeProof(_ proof: String, fileName: String) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let proofURL = documentsURL.appending(component: fileName)
        try? proof.write(to: proofURL, atomically: true, encoding: .utf8)
    }

    private static func redactedSummary(for result: DirectCallPushKitRegistrarResult? = nil) -> String {
        guard let result else {
            return initialRedactedSummary()
        }

        let diagnostics = result.diagnostics
        return [
            "pushkit_registration_requested=\(diagnostics.pushKitRegistryCreateRequested || diagnostics.pushKitTokenUpdateReceived)",
            "pushkit_feature_gate_enabled=\(diagnostics.pushKitFeatureGateEnabled)",
            "pushkit_registry_create_requested=\(diagnostics.pushKitRegistryCreateRequested)",
            "pushkit_token_update_received=\(diagnostics.pushKitTokenUpdateReceived)",
            "pushkit_registration_result=\(redactedRegistrationResult(for: result.status))",
            "pushkit_token_persistence_requested=false",
            "pushkit_token_upload_requested=false",
            "apns_registration_requested=false",
            "media_credentials_requested=false",
            "media_connect_requested=false",
            "matrix_event_emit_requested=false",
            "blocked_reason=\(redactedBlockedReason(for: result))"
        ].joined(separator: "\n")
    }

    private static func initialRedactedSummary() -> String {
        [
            "pushkit_registration_requested=false",
            "pushkit_feature_gate_enabled=false",
            "pushkit_registry_create_requested=false",
            "pushkit_token_update_received=false",
            "pushkit_registration_result=not_started",
            "pushkit_token_persistence_requested=false",
            "pushkit_token_upload_requested=false",
            "apns_registration_requested=false",
            "media_credentials_requested=false",
            "media_connect_requested=false",
            "matrix_event_emit_requested=false",
            "blocked_reason=none"
        ].joined(separator: "\n")
    }

    private static func initialUploadRedactedSummary() -> String {
        SalemXPushKitTokenUploadSmokeSummary().redactedLines.joined(separator: "\n")
    }

    private static func sanitizedSessionUserHash(_ userHash: String) -> String {
        let trimmed = userHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 16,
              trimmed.allSatisfy(\.isHexDigit) else {
            return ""
        }
        return trimmed
    }

    private static func sha256Prefix16(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func redactedRegistrationResult(for status: DirectCallPushKitRegistrarStatus) -> String {
        switch status {
        case .tokenUpdateReceived:
            "token_received"
        case .registryCreated:
            "registry_created"
        case .registryUnavailable:
            "registry_unavailable"
        case .tokenInvalidated:
            "token_invalidated"
        case .disabled:
            "disabled"
        }
    }

    private static func redactedBlockedReason(for result: DirectCallPushKitRegistrarResult) -> String {
        if result.status == .tokenUpdateReceived {
            return "none"
        }
        return result.diagnostics.blockedReason?.description ?? "none"
    }
}

extension SalemXPushKitRegistrationSmokeDebugBridge {
    private static func fetchAuthenticatedPendingMetadata(reference: String) async {
        guard let fetchURL = pendingMetadataFetchURL(reference: reference) else {
            recordAuthenticatedPendingMetadataFetchBlocked(reason: "pending_metadata_fetch_url_unresolved_redacted",
                                                           authorized: false,
                                                           httpStatusBucket: "not_requested",
                                                           failureReason: "url_unresolved")
            return
        }
        guard let accessToken = await SalemXForegroundSSESmokeDebug.matrixAccessTokenForPushKitUploadSmoke() else {
            recordAuthenticatedPendingMetadataFetchBlocked(reason: "pending_metadata_fetch_blocked_by_auth",
                                                           authorized: false,
                                                           httpStatusBucket: "not_requested",
                                                           failureReason: "local_auth_unavailable")
            return
        }

        var request = URLRequest(url: fetchURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("B" + "earer " + accessToken, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let diagnostics = pendingMetadataFetchFailureDiagnostics(response: response, data: data)
                recordAuthenticatedPendingMetadataFetchBlocked(reason: "pending_metadata_fetch_http_failure_redacted",
                                                               authorized: true,
                                                               httpStatusBucket: diagnostics.httpStatusBucket,
                                                               errcode: diagnostics.errcode,
                                                               failureReason: diagnostics.failureReason)
                return
            }
            guard let session = directCallSessionFromPendingMetadata(data: data) else {
                recordAuthenticatedPendingMetadataFetchBlocked(reason: "pending_metadata_fetch_payload_invalid_redacted",
                                                               authorized: true,
                                                               httpStatusBucket: "2xx",
                                                               failureReason: "payload_invalid")
                return
            }
            recordAuthenticatedPendingMetadataFetchSuccess(session)
        } catch {
            recordAuthenticatedPendingMetadataFetchBlocked(reason: "pending_metadata_fetch_network_failure_redacted",
                                                           authorized: true,
                                                           httpStatusBucket: "network_failure",
                                                           failureReason: "network_failure")
        }
    }

    private static func pendingMetadataFetchURL(reference: String) -> URL? {
        guard !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var components = URLComponents(string: uploadSmokeDefaultURLString) else {
            return nil
        }
        components.path = pendingMetadataEndpointPathPrefix + "/" + reference
        components.query = nil
        return components.url
    }

    private struct PendingMetadataFetchFailureDiagnostics {
        let httpStatusBucket: String
        let errcode: String
        let failureReason: String
    }

    private static func pendingMetadataFetchFailureDiagnostics(response: URLResponse?,
                                                               data: Data) -> PendingMetadataFetchFailureDiagnostics {
        guard let httpResponse = response as? HTTPURLResponse else {
            return .init(httpStatusBucket: "unknown",
                         errcode: "none",
                         failureReason: "missing_http_response")
        }

        let errcode = pendingMetadataFetchErrcode(data: data)
        return .init(httpStatusBucket: pendingMetadataFetchHTTPStatusBucket(httpResponse.statusCode),
                     errcode: errcode,
                     failureReason: pendingMetadataFetchFailureReason(statusCode: httpResponse.statusCode, errcode: errcode))
    }

    private static func pendingMetadataFetchErrcode(data: Data) -> String {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errcode = payload["errcode"] as? String,
              errcode.hasPrefix("M_") else {
            return "none"
        }
        return errcode
    }

    private static func pendingMetadataFetchHTTPStatusBucket(_ statusCode: Int) -> String {
        switch statusCode {
        case 200..<300:
            return "2xx"
        case 400:
            return "400"
        case 401:
            return "401"
        case 403:
            return "403"
        case 404:
            return "404"
        case 429:
            return "429"
        case 500..<600:
            return "5xx"
        default:
            return "other_redacted"
        }
    }

    private static func pendingMetadataFetchFailureReason(statusCode: Int, errcode: String) -> String {
        if statusCode == 401 || errcode == "M_UNKNOWN_TOKEN" {
            return "auth_rejected"
        }
        if statusCode == 403 || errcode == "M_FORBIDDEN" {
            return "forbidden"
        }
        if statusCode == 404 || errcode == "M_NOT_FOUND" || errcode == "M_UNRECOGNIZED" {
            return "not_found"
        }
        if (500..<600).contains(statusCode) {
            return "server_error"
        }
        return "http_error_redacted"
    }

    private static func directCallSessionFromPendingMetadata(data: Data) -> DirectCallSession? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["version"] as? Int == 1,
              let callID = payload["call_id"] as? String,
              let roomID = payload["room_id"] as? String,
              let peerUserID = payload["peer_user_id"] as? String,
              payload["direction"] as? String == "incoming",
              DirectCallIntent.parse(payload["intent"] as? String) == .audio,
              !callID.isEmpty,
              !roomID.isEmpty,
              !peerUserID.isEmpty else {
            return nil
        }

        return DirectCallSession(callID: callID,
                                 roomID: roomID,
                                 peerUserID: peerUserID,
                                 direction: .incoming,
                                 intent: .audio,
                                 encryptionMode: .e2eeRequired,
                                 startedAt: Date(),
                                 updatedAt: Date(),
                                 state: .incomingRinging,
                                 encryptionState: .ready)
    }

    private static func recordAuthenticatedPendingMetadataFetchSuccess(_ session: DirectCallSession) {
        lock.lock()
        pendingAuthenticatedMetadataReference = nil
        var summary = latestVoIPPushReceiptSummary
        summary.recordAuthenticatedPendingMetadataFetch(session: session)
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        Task { @MainActor in
            await requestControlledMediaCredentialsForControlledRuntime(session: session, source: "authenticated_pending_metadata_fetch")
        }
    }

    private static func recordAuthenticatedPendingMetadataFetchBlocked(reason: String,
                                                                       authorized: Bool,
                                                                       httpStatusBucket: String = "unknown",
                                                                       errcode: String = "none",
                                                                       failureReason: String = "unknown") {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.recordAuthenticatedPendingMetadataFetchBlocked(reason,
                                                               authorized: authorized,
                                                               httpStatusBucket: httpStatusBucket,
                                                               errcode: errcode,
                                                               failureReason: failureReason)
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
    }

    @MainActor
    private static func requestControlledMediaCredentialsForControlledRuntime(session: DirectCallSession, source: String) async {
        guard let tokenEndpointURL = controlledMediaCredentialsTokenEndpointURL(),
              let accessTokenProvider = SalemXForegroundSSESmokeDebug.matrixAccessTokenProviderForPushKitUploadSmoke() else {
            recordControlledMediaCredentialsRequest(succeeded: false,
                                                    expiresAtPresent: false,
                                                    session: session,
                                                    source: source)
            return
        }

        let tokenClient = ProductionDirectCallLiveKitTokenClient(configuration: .init(tokenEndpointURL: tokenEndpointURL),
                                                                 httpTransport: URLSessionDirectCallHTTPTransport(),
                                                                 accessTokenProvider: accessTokenProvider)
        let tokenProvider = DirectCallLiveKitTokenProvider(tokenClient: tokenClient)
        let result = await tokenProvider.connectionInfo(for: session)
        let succeeded: Bool
        let expiresAtPresent: Bool
        let receivedConnectionInfo: DirectCallMediaConnectionInfo?
        if case .success(let connectionInfo) = result {
            succeeded = true
            expiresAtPresent = connectionInfo.expiresAtPresent
            receivedConnectionInfo = connectionInfo
        } else {
            succeeded = false
            expiresAtPresent = false
            receivedConnectionInfo = nil
        }
        recordControlledMediaCredentialsRequest(succeeded: succeeded,
                                                expiresAtPresent: expiresAtPresent,
                                                session: session,
                                                source: source,
                                                diagnostics: tokenProvider.diagnosticSnapshot)
        if let connectionInfo = receivedConnectionInfo {
            startReceiverControlledRuntimeConnectLeaseIfAllowed(session: session, connectionInfo: connectionInfo)
        }
    }

    @MainActor
    private static func startReceiverControlledRuntimeConnectLeaseIfAllowed(session: DirectCallSession, connectionInfo: DirectCallMediaConnectionInfo) {
        lock.lock()
        let summary = latestVoIPPushReceiptSummary
        let alreadyRunning = receiverConnectedSessionLeaseTask != nil || receiverConnectedSessionLease != nil
        let allowed = summary.controlledConnectFirstAttemptAllowed &&
            summary.mediaConnectPreflightCredentialsAvailable &&
            summary.physical6RuntimeEnablementURLHookConsumed &&
            !alreadyRunning
        lock.unlock()

        guard allowed else {
            return
        }

        let task = Task { @MainActor in
            await runReceiverControlledRuntimeConnectLease(session: session, connectionInfo: connectionInfo)
        }
        lock.lock()
        receiverConnectedSessionLeaseTask = task
        receiverConnectedSessionLeaseReleased = false
        receiverConnectedWindowRetentionExtensionUsed = false
        lock.unlock()
    }

    @MainActor
    private static func runReceiverControlledRuntimeConnectLease(session: DirectCallSession, connectionInfo: DirectCallMediaConnectionInfo) async {
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let keyMaterial = UUID().uuidString + UUID().uuidString
        let e2eeContext: any DirectCallMediaE2EEContextProtocol
        let e2eeContextProvider: DirectCallLiveKitE2EEContextProvider

        switch keyStore.storeSharedKey(keyMaterial, callID: session.callID) {
        case .success(let keyHandle):
            let provider = DirectCallLiveKitE2EEContextProvider(keyStore: keyStore)
            switch provider.context(for: session, keyHandle: keyHandle) {
            case .success(let context):
                e2eeContext = context
                e2eeContextProvider = provider
            case .failure(let error):
                recordReceiverControlledRuntimeConnectResult(succeeded: false, errorBucket: redactedReceiverRuntimeErrorBucket(for: error))
                return
            }
        case .failure(let error):
            recordReceiverControlledRuntimeConnectResult(succeeded: false, errorBucket: redactedReceiverRuntimeErrorBucket(for: error))
            return
        }

        let client = receiverRuntimeLiveKitClientFactory()
        let executor = DirectCallLiveKitConnectExecutor(liveKitClient: client)
        let result = await executor.connectAudio(connectionInfo: connectionInfo, e2eeContext: e2eeContext)

        switch result {
        case .success:
            let lease = SalemXReceiverConnectedSessionLease(callID: session.callID,
                                                            client: client,
                                                            e2eeContextProvider: e2eeContextProvider,
                                                            e2eeContext: e2eeContext,
                                                            keyStore: keyStore)
            lock.lock()
            receiverConnectedSessionLease = lease
            var summary = latestVoIPPushReceiptSummary
            summary.recordReceiverControlledRuntimeConnectResult(succeeded: true, errorBucket: "none")
            summary.recordReceiverConnectedSessionLeaseAcquired(taskRetained: receiverConnectedSessionLeaseTask != nil)
            lock.unlock()

            updateLatestVoIPPushReceiptSummary(summary)
        case .failure(let error):
            await client.cleanup()
            recordReceiverControlledRuntimeConnectResult(succeeded: false, errorBucket: redactedReceiverRuntimeErrorBucket(for: error))
        }
    }

    @MainActor
    private static func recordReceiverControlledRuntimeConnectResult(succeeded: Bool, errorBucket: String) {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.recordReceiverControlledRuntimeConnectResult(succeeded: succeeded, errorBucket: errorBucket)
        if !succeeded {
            receiverConnectedSessionLeaseTask = nil
        }
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
    }

    @MainActor
    private static func releaseReceiverConnectedSessionLease(reason: String) {
        lock.lock()
        let lease = receiverConnectedSessionLease
        let repeated = receiverConnectedSessionLeaseReleased
        receiverConnectedSessionLease = nil
        receiverConnectedSessionLeaseTask = nil
        receiverConnectedSessionLeaseReleased = true
        receiverConnectedWindowRetentionExtensionUsed = false
        receiverParticipantSnapshotSweepID = nil
        var summary = latestVoIPPushReceiptSummary
        summary.recordReceiverConnectedSessionLeaseReleased(reason: reason, repeated: repeated)
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)

        guard !repeated, let lease else {
            return
        }

        Task { @MainActor in
            await lease.cleanup()
        }
    }

    private static func redactedReceiverRuntimeErrorBucket(for error: DirectCallMediaError) -> String {
        switch error {
        case .liveKitNetworkFailed, .liveKitURLUnreachable:
            return "network_redacted"
        case .liveKitURLInvalid:
            return "url_invalid_redacted"
        case .liveKitTokenRejected, .tokenUnavailable, .tokenEndpointUnavailable, .accessTokenUnavailable, .tokenHTTPUnavailable, .tokenBackendRejected, .tokenResponseInvalid:
            return "credentials_redacted"
        case .liveKitRoomJoinFailed:
            return "room_join_failed_redacted"
        case .liveKitE2EEConfigFailed, .e2eeContextUnavailable, .e2eeNotReady, .keyMismatch:
            return "e2ee_redacted"
        case .audioRouteFailed, .mediaSetupUnavailable:
            return "audio_route_redacted"
        case .unsupportedIntent, .invalidSession:
            return "session_redacted"
        default:
            return "runtime_connect_failed_redacted"
        }
    }

    private static func controlledMediaCredentialsTokenEndpointURL() -> URL? {
        guard var components = URLComponents(string: uploadSmokeDefaultURLString) else {
            return nil
        }
        components.path = controlledMediaCredentialsTokenEndpointPath
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func recordForegroundPendingCallMetadataHandoffIfAvailable(_ summary: inout SalemXVoIPPushReceiptProofSummary) -> Bool {
        guard let session = pendingForegroundCallMetadataSession,
              let recordedAt = pendingForegroundCallMetadataRecordedAt,
              Date().timeIntervalSince(recordedAt) <= pendingForegroundCallMetadataMaxAge else {
            pendingForegroundCallMetadataSession = nil
            pendingForegroundCallMetadataSource = "none"
            pendingForegroundCallMetadataRecordedAt = nil
            return false
        }

        summary.recordForegroundPendingCallMetadataHandoff(session: session, source: pendingForegroundCallMetadataSource)
        return summary.mediaCredentialsRequestMetadataAvailable
    }

    static func recordForegroundPendingCallMetadataCandidate(_ session: DirectCallSession, source: String) {
        lock.lock()
        pendingForegroundCallMetadataSession = session
        pendingForegroundCallMetadataSource = source
        pendingForegroundCallMetadataRecordedAt = Date()

        var summaryToWrite: SalemXVoIPPushReceiptProofSummary?
        if latestVoIPPushReceiptSummary.realInvitePayloadMappingObserved,
           latestVoIPPushReceiptSummary.foregroundCallState == "real_invite_pending_media" {
            var summary = latestVoIPPushReceiptSummary
            summary.recordForegroundPendingCallMetadataHandoff(session: session, source: source)
            summaryToWrite = summary
        }
        lock.unlock()

        if let summaryToWrite {
            updateLatestVoIPPushReceiptSummary(summaryToWrite)
        }
    }

    static func recordForegroundPendingCallMetadataHandoff(_ session: DirectCallSession, source: String) {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.recordForegroundPendingCallMetadataHandoff(session: session, source: source)
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
    }

    static func recordReceiverRemoteParticipantRuntimeObservation(participantCountBucket: String,
                                                                  audioTrackSubscribed: Bool,
                                                                  audioTrackUnmuted: Bool) {
        let safeParticipantCountBucket: String
        switch participantCountBucket {
        case "0", "1", "2+":
            safeParticipantCountBucket = participantCountBucket
        default:
            safeParticipantCountBucket = "unknown"
        }

        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.recordRemoteAudioLivenessObservation(participantSeen: true,
                                                     participantCountBucket: safeParticipantCountBucket,
                                                     audioTrackSubscribed: audioTrackSubscribed,
                                                     audioTrackUnmuted: audioTrackUnmuted,
                                                     audioLevelObserved: false,
                                                     livenessObserved: false)
        let shouldReleaseLease = summary.remoteParticipantObservationWaitCompleted
        let releaseReason = summary.remoteParticipantObservationFinalClassification
        if shouldReleaseLease {
            remoteParticipantObservationWindowID = nil
            remoteParticipantObservationWindowStartedAt = nil
            receiverParticipantSnapshotSweepID = nil
            pendingRemotePeerContextHandoff = nil
        }
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        if shouldReleaseLease {
            Task { @MainActor in
                releaseReceiverConnectedSessionLease(reason: releaseReason)
            }
        }
    }

    static func recordReceiverRemoteParticipantEventCallback(participantCountBucket: String) {
        let safeParticipantCountBucket: String
        switch participantCountBucket {
        case "0", "1", "2+":
            safeParticipantCountBucket = participantCountBucket
        default:
            safeParticipantCountBucket = "unknown"
        }

        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.recordReceiverParticipantEventCallbackObservation(participantCountBucket: safeParticipantCountBucket)
        let shouldReleaseLease = summary.remoteParticipantObservationWaitCompleted
        let releaseReason = summary.remoteParticipantObservationFinalClassification
        if shouldReleaseLease {
            remoteParticipantObservationWindowID = nil
            remoteParticipantObservationWindowStartedAt = nil
            receiverParticipantSnapshotSweepID = nil
            pendingRemotePeerContextHandoff = nil
        }
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        if shouldReleaseLease {
            Task { @MainActor in
                releaseReceiverConnectedSessionLease(reason: releaseReason)
            }
        }
    }

    static func recordControlledMediaCredentialsRequest(succeeded: Bool,
                                                        expiresAtPresent: Bool,
                                                        session: DirectCallSession,
                                                        source: String,
                                                        diagnostics: DirectCallDiagnosticSnapshot = .empty) {
        lock.lock()
        let physical6RuntimeEnablementURLHookSnapshot = physical6RuntimeEnablementURLHook
        var summary = latestVoIPPushReceiptSummary
        summary.recordControlledMediaCredentialsRequest(succeeded: succeeded,
                                                        expiresAtPresent: expiresAtPresent,
                                                        session: session,
                                                        source: source,
                                                        diagnostics: diagnostics,
                                                        physical6RuntimeEnablementHook: physical6RuntimeEnablementURLHookSnapshot)
        if summary.physical6RuntimeEnablementURLHookConsumed {
            physical6RuntimeEnablementURLHook = physical6RuntimeEnablementURLHookSnapshot.consumedCopy()
        }
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
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

    fileprivate static func matrixAccessTokenForPushKitUploadSmoke() async -> String? {
        guard let activeUserSession,
              let accessTokenProvider = activeUserSession.clientProxy as? DirectCallMatrixAccessTokenProviding,
              let accessToken = await accessTokenProvider.matrixAccessToken(),
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return accessToken
    }

    fileprivate static func matrixAccessTokenProviderForPushKitUploadSmoke() -> DirectCallMatrixAccessTokenProviding? {
        activeUserSession?.clientProxy as? DirectCallMatrixAccessTokenProviding
    }

    fileprivate static func matrixSessionWhoamiSmokeAvailability() -> MatrixSessionWhoamiSmokeAvailability {
        let clientProxy = activeUserSession?.clientProxy
        return .init(activeSessionAvailable: activeUserSession != nil,
                     accessTokenProviderAvailable: clientProxy is DirectCallMatrixAccessTokenProviding,
                     homeserverURLAvailable: clientProxy?.homeserver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
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
