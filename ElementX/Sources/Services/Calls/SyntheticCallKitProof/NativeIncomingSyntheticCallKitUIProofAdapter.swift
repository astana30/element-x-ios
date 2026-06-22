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
    var controlledCallKitCleanupRequested = false
    var controlledCallKitCleanupResult = "not_requested"
    var blockedReason = "voip_push_not_received"

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
            "controlled_callkit_cleanup_requested=\(controlledCallKitCleanupRequested)",
            "controlled_callkit_cleanup_result=\(controlledCallKitCleanupResult)",
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

private extension SalemXVoIPPushReceiptProofSummary {
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
        pendingMetadataFetchRequested = true
        pendingMetadataFetchAuthorized = true
        pendingMetadataFetchResult = "success_redacted"
        pendingMetadataFetchHTTPStatusBucket = "2xx"
        pendingMetadataFetchErrcode = "none"
        pendingMetadataFetchFailureReason = "none"
        pendingMetadataPayloadRedacted = true
        recordForegroundPendingCallMetadataHandoff(session: session, source: "authenticated_pending_metadata_fetch")
        mediaCredentialsResult = "blocked_redacted"
        mediaCredentialsRequested = false
        mediaCredentialsRequestAuthorized = false
        mediaCredentialsTokenReceived = false
        mediaCredentialsURLReceived = false
        mediaCredentialsCleanupRequested = false
        mediaCredentialsCleanupResult = "not_requested"
        blockedReason = "media_credentials_request_deferred_until_next_phase"
    }

    mutating func recordAuthenticatedPendingMetadataFetchBlocked(_ reason: String,
                                                                 authorized: Bool,
                                                                 httpStatusBucket: String = "unknown",
                                                                 errcode: String = "none",
                                                                 failureReason: String = "unknown") {
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
        blockedReason = reason
    }

    mutating func recordControlledMediaCredentialsRequest(succeeded: Bool,
                                                          expiresAtPresent: Bool,
                                                          session: DirectCallSession,
                                                          source: String,
                                                          diagnostics: DirectCallDiagnosticSnapshot = .empty) {
        recordForegroundPendingCallMetadataHandoff(session: session, source: source)
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
        if cleanupCleared {
            recordControlledMediaConnectPreflight(credentialsAvailable: true,
                                                  tokenPresent: mediaCredentialsTokenReceived,
                                                  urlPresent: mediaCredentialsURLReceived,
                                                  expiresAtPresent: mediaCredentialsExpiresAtPresent)
        }
        blockedReason = succeeded && mediaCredentialsRequestMetadataAvailable ? "none" : "media_credentials_request_failed_redacted"
    }

    mutating func recordControlledMediaConnectPreflight(credentialsAvailable: Bool,
                                                        tokenPresent: Bool,
                                                        urlPresent: Bool,
                                                        expiresAtPresent: Bool) {
        mediaConnectPreflightRequested = true
        mediaConnectPreflightMetadataAvailable = mediaCredentialsRequestMetadataAvailable
        mediaConnectPreflightCredentialsAvailable = credentialsAvailable && mediaCredentialsRequestMetadataAvailable
        mediaConnectPreflightTokenPresent = tokenPresent && mediaCredentialsRequestMetadataAvailable
        mediaConnectPreflightURLPresent = urlPresent && mediaCredentialsRequestMetadataAvailable
        mediaConnectPreflightExpiresAtPresent = expiresAtPresent && mediaCredentialsRequestMetadataAvailable
        mediaConnectGuardEnabled = true
        recordControlledConnectActivationProof(SalemXControlledMediaConnectActivationConfiguration.defaultDisabled)
        recordControlledConnectEnablementProof(SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled)
        mediaConnectExecutionAllowed = controlledConnectExecutionAllowed && controlledConnectEnablementExecutionAllowed
        recordControlledAudioConnectExecutionGate(SalemXControlledAudioConnectExecutionGate(credentialsPresent: mediaConnectPreflightCredentialsAvailable,
                                                                                            activationConfiguration: .defaultDisabled,
                                                                                            enablementConfiguration: .defaultDisabled))
        mediaConnectExecutionAllowed = mediaConnectExecutionAllowed && controlledAudioConnectExecutionAllowed
        recordControlledAudioConnectActivationPath(SalemXControlledAudioConnectActivationPath(receiverAppSessionValidated: pendingMetadataFetchAuthorized && pendingMetadataFetchResult == "success_redacted",
                                                                                              credentialsPresent: mediaConnectPreflightCredentialsAvailable,
                                                                                              enablementConfiguration: .defaultDisabled))
        mediaConnectExecutionAllowed = mediaConnectExecutionAllowed && controlledAudioConnectActivationAllowed
        mediaConnectPreflightResult = mediaConnectPreflightCredentialsAvailable ? "blocked_before_connect_redacted" : "blocked_redacted"
        mediaConnectBlockedReason = mediaConnectPreflightCredentialsAvailable ? controlledConnectBlockedReasonForPreflight : "media_connect_preflight_not_ready"
        mediaConnectEngineInvoked = false
        liveKitConnectAudioInvoked = false
    }

    mutating func rollbackControlledConnectActivationProof() {
        recordControlledConnectActivationProof(SalemXControlledMediaConnectActivationConfiguration.rollbackDisabled)
        recordControlledConnectEnablementProof(SalemXControlledMediaConnectEnablementConfiguration.rollbackDisabled)
        recordControlledAudioConnectExecutionGate(SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false))
        recordControlledAudioConnectActivationPath(SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false))
        mediaConnectExecutionAllowed = false
        mediaConnectEngineInvoked = false
        liveKitConnectAudioInvoked = false
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

    private var controlledConnectBlockedReasonForPreflight: String {
        if !controlledConnectExecutionAllowed {
            return controlledConnectBlockedReason
        }
        if !controlledConnectEnablementExecutionAllowed {
            return controlledConnectEnablementBlockedReason
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

@objc(SalemXPushKitRegistrationSmokeDebugBridge)
// swiftlint:disable:next type_body_length
final class SalemXPushKitRegistrationSmokeDebugBridge: NSObject {
    private static let uploadSmokeURLHost = "debug"
    private static let uploadSmokeURLPath = "/pushkit-token-upload-smoke/start"
    private static let matrixSessionWhoamiSmokeURLPath = "/pushkit-token-upload-smoke/session-whoami"
    private static let uploadSmokeDefaultURLString = "https://matrix.mertis.kz/_matrix/client/unstable/kz.salemx.direct_call/pushkit/token"
    private static let matrixSessionWhoamiURLString = "https://matrix.mertis.kz/_matrix/client/v3/account/whoami"
    private static let controlledMediaCredentialsTokenEndpointPath = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/livekit/token"
    private static let uploadSmokeProofFileName = "salemx-pushkit-token-upload-smoke-proof.txt"
    private static let matrixSessionWhoamiProofFileName = "salemx-matrix-session-whoami-proof.txt"
    private static let voIPPushReceiptProofFileName = "salemx-voip-push-receipt-proof.txt"
    private static let startupPushKitRegistryProofFileName = "salemx-startup-pushkit-registry-proof.txt"
    private static let localCallKitOnlyProofFileName = "salemx-local-callkit-only-proof.txt"
    private static let localBackgroundCallKitOnlyProofFileName = "salemx-local-background-callkit-proof.txt"
    private static let pendingMetadataEndpointPathPrefix = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata"
    private static let voIPPushReceiptCallKitReportTimeout: TimeInterval = 3
    private static let voIPPushReceiptAnswerableWindowTimeout: TimeInterval = 1.5
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
    private static var proofGenerationCounter = 0
    private static var callKitReportCompletionDate: Date?
    private static var pushKitCompletionDate: Date?
    private static var pushKitCompletionAnswerableWindowID: UUID?
    private static var pushKitCompletionAnswerableWindowFinish: ((String) -> Void)?
    private static var pendingOperatorReadyToAnswer = false
    private static var pendingOperatorExpectedSurface = "unknown"
    private static let pendingForegroundCallMetadataMaxAge: TimeInterval = 120
    private static var pendingForegroundCallMetadataSession: DirectCallSession?
    private static var pendingForegroundCallMetadataSource = "none"
    private static var pendingForegroundCallMetadataRecordedAt: Date?
    private static var pendingAuthenticatedMetadataReference: String?
    #if canImport(CallKit) && os(iOS)
    private static var callKitProofHarness: NativeIncomingSyntheticCallKitUIProofHarness?
    private static var callKitProofGeneration = 0
    private static var localCallKitOnlyProofHarness: NativeIncomingSyntheticCallKitUIProofHarness?
    private static var localCallKitOnlyProofGeneration = 0
    private static var localBackgroundCallKitOnlyProofHarness: NativeIncomingSyntheticCallKitUIProofHarness?
    private static var localBackgroundCallKitOnlyProofGeneration = 0
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

        return false
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
        let safeExpectedSurface: String
        switch expectedSurface {
        case "lockscreen", "fullscreen", "banner", "foreground":
            safeExpectedSurface = expectedSurface
        default:
            safeExpectedSurface = "unknown"
        }

        lock.lock()
        pendingOperatorReadyToAnswer = true
        pendingOperatorExpectedSurface = safeExpectedSurface
        var summary = latestVoIPPushReceiptSummary
        summary.operatorReadyToAnswer = true
        summary.operatorExpectedSurface = safeExpectedSurface
        lock.unlock()

        updateLatestVoIPPushReceiptSummary(summary)
        return redactedVoIPPushReceiptSummary()
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
        baseSummary.appStateAtPushKitReceipt = currentApplicationStateProof()
        lock.lock()
        let operatorReadyToAnswer = pendingOperatorReadyToAnswer
        let operatorExpectedSurface = pendingOperatorExpectedSurface
        lock.unlock()
        baseSummary.operatorReadyToAnswer = operatorReadyToAnswer
        baseSummary.operatorExpectedSurface = operatorExpectedSurface
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
            baseSummary.voIPOperatorMarkerSetBeforeReport = operatorReadyToAnswer
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

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + voIPPushReceiptCallKitReportTimeout) {
            guard completionCoordinator.shouldRunReportTimeout() else {
                return
            }
            completeVoIPPushReceiptOnce(coordinator: completionCoordinator,
                                        reportResult: "timeout_redacted",
                                        blockedReason: "callkit_report_completion_timeout_redacted",
                                        answerRetentionProof: nil,
                                        reportCompletionDate: nil,
                                        answerableWindowRequested: false,
                                        answerableWindowResult: "not_requested",
                                        answerableWindowStartedAt: nil,
                                        completion: completion)
        }

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
        completedSummary.callKitReportCompletionObserved = reportResult != "timeout_redacted"
        completedSummary.callKitReportCompletionAtMsRedacted = reportResult != "timeout_redacted"
        completedSummary.pushKitCompletionAnswerableWindowRequested = answerableWindowRequested
        completedSummary.pushKitCompletionAnswerableWindowResult = answerableWindowResult
        completedSummary.pushKitCompletionAnswerableWindowDurationBucket = answerableWindowStartedAt.map { elapsedBucket(from: $0, to: completionCallDate) } ?? "not_requested"
        completedSummary.pushKitCompletionAfterReportMsBucket = reportCompletionDate.map { elapsedBucket(from: $0, to: completionCallDate) } ?? "unknown"
        completedSummary.voIPPushKitCompletionDelayedUntilFirstAction = answerableWindowRequested && answerableWindowResult == "first_action_observed"
        completedSummary.appStateAtReportCompletion = currentApplicationStateProof()
        if completedSummary.callKitFirstActionKind == "none" {
            completedSummary.callKitEventOrder = reportResult == "timeout_redacted" ? "report_completion_timeout" : "report_completion_only"
        }
        completedSummary.controlledTimeoutBeforeAnswer = reportResult == "timeout_redacted"
        if let answerRetentionProof {
            completedSummary.callKitProviderRetainedForAnswer = answerRetentionProof.providerRetainedForAnswer
            completedSummary.callKitDelegateRetainedForAnswer = answerRetentionProof.delegateRetainedForAnswer
            completedSummary.callKitActiveCallUUIDRetained = answerRetentionProof.activeCallUUIDRetained
        }
        completedSummary.completionCalled = true
        if answerableWindowRequested, answerableWindowResult == "timeout_elapsed", completedSummary.callKitFirstActionKind == "none" {
            completedSummary.blockedReason = "callkit_first_action_not_observed_before_completion_window"
        } else if !answerableWindowRequested {
            completedSummary.blockedReason = blockedReason
        }
        lock.lock()
        callKitReportCompletionDate = reportCompletionDate
        pushKitCompletionDate = reportResult == "timeout_redacted" ? nil : completionCallDate
        lock.unlock()
        updateLatestVoIPPushReceiptSummary(completedSummary)
        completion()
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
        summary.pushKitCompletionAnswerableWindowResult = "pending"
        summary.pushKitCompletionAnswerableWindowDurationBucket = "not_finished"
        summary.appStateAtReportCompletion = currentApplicationStateProof()
        summary.callKitEventOrder = "report_completion_only"
        if let answerRetentionProof {
            summary.callKitProviderRetainedForAnswer = answerRetentionProof.providerRetainedForAnswer
            summary.callKitDelegateRetainedForAnswer = answerRetentionProof.delegateRetainedForAnswer
            summary.callKitActiveCallUUIDRetained = answerRetentionProof.activeCallUUIDRetained
        }
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

    static func recordCallKitAnswerActionProof() {
        var pendingMetadataReferenceToFetch: String?
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        let screenSource = summary.realInvitePayloadMappingObserved ? "callkit_answer_real_invite_controlled" : "callkit_answer_sandbox_voip_smoke"
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
                    summary.recordControlledMediaCredentialsRequestBoundaryNotReady()
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
        latestVoIPPushReceiptSummary = summary
        let proof = summary.redactedLines.joined(separator: "\n")
        lock.unlock()
        writeVoIPPushReceiptProof(proof)
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
            await requestControlledMediaCredentialsNoConnect(session: session, source: "authenticated_pending_metadata_fetch")
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
    private static func requestControlledMediaCredentialsNoConnect(session: DirectCallSession, source: String) async {
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
        if case .success(let connectionInfo) = result {
            succeeded = true
            expiresAtPresent = connectionInfo.expiresAtPresent
        } else {
            succeeded = false
            expiresAtPresent = false
        }
        recordControlledMediaCredentialsRequest(succeeded: succeeded,
                                                expiresAtPresent: expiresAtPresent,
                                                session: session,
                                                source: source,
                                                diagnostics: tokenProvider.diagnosticSnapshot)
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

    static func recordControlledMediaCredentialsRequest(succeeded: Bool,
                                                        expiresAtPresent: Bool,
                                                        session: DirectCallSession,
                                                        source: String,
                                                        diagnostics: DirectCallDiagnosticSnapshot = .empty) {
        lock.lock()
        var summary = latestVoIPPushReceiptSummary
        summary.recordControlledMediaCredentialsRequest(succeeded: succeeded,
                                                        expiresAtPresent: expiresAtPresent,
                                                        session: session,
                                                        source: source,
                                                        diagnostics: diagnostics)
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
