//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

struct NativeIncomingSyntheticCallKitUIProofTests {
    @Test
    func rejectsEmptyAndUnsafeDisplayMetadata() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)
        let identity = safeIdentity()

        let emptyResult = adapter.reportSyntheticIncomingCall(identity: identity, displayLabel: "")
        let unsafeResult = adapter.reportSyntheticIncomingCall(identity: identity, displayLabel: "unsafe@label")

        #expect(emptyResult == .failed(.malformed))
        #expect(unsafeResult == .failed(.malformed))
        #expect(reporter.reportedCalls.isEmpty)
        #expect(eventRecorder.events == [.failed(.malformed), .failed(.malformed)])
    }

    @Test
    func reportsThroughInjectedReporterOnly() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)

        let result = adapter.reportSyntheticIncomingCall(identity: safeIdentity(), displayLabel: "Pilot Participant")

        #expect(result == .reported)
        #expect(reporter.reportedCalls.count == 1)
        #expect(actionHandler.answeredIdentities.isEmpty)
        #expect(eventRecorder.events == [.reported])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func answerCallbackIsDisabledLocalOnly() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)
        let identity = safeIdentity()
        _ = adapter.reportSyntheticIncomingCall(identity: identity, displayLabel: "Pilot Participant")

        reporter.simulateAnswer()

        #expect(actionHandler.answeredIdentities == [identity])
        #expect(actionHandler.endedIdentities.isEmpty)
        #expect(eventRecorder.events == [.reported, .answered])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func answerCallbackRoutesToIncomingStateMachineSurface() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let actionRouter = DisabledNativeIncomingCallStateMachineActionRouter(stateStore: stateStore,
                                                                              diagnosticsRecorder: dependencies.diagnosticsRecorder)
        let actionHandler = NativeIncomingCallStateMachineSyntheticActionHandler(actionRouter: actionRouter)
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)
        let identity = safeIdentity()

        let result = adapter.reportSyntheticIncomingCall(identity: identity, displayLabel: "Pilot Participant")
        reporter.simulateAnswer()

        #expect(result == .reported)
        #expect(stateStore.state(for: identity.handle) == .answerRequested)
        #expect(actionRouter.answerRequestCount == 1)
        #expect(eventRecorder.events == [.reported, .answered])
        #expect(dependencies.diagnosticsRecorder.diagnostics.contains { diagnostics in
            diagnostics.lifecycleState == .answerRequested &&
                diagnostics.mediaCredentialRequested == false &&
                diagnostics.mediaConnectAttempted == false
        })
        #expect(!String(describing: actionHandler).contains("displayCall"))
        #expect(!String(describing: actionHandler).contains("presentCallScreen"))
    }

    @Test
    func answerCallbackRequiresForegroundAcceptanceBeforeMediaAllowance() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let actionRouter = DisabledNativeIncomingCallStateMachineActionRouter(stateStore: stateStore,
                                                                              diagnosticsRecorder: dependencies.diagnosticsRecorder)
        let actionHandler = NativeIncomingCallStateMachineSyntheticActionHandler(actionRouter: actionRouter)
        let authorizer = NativeIncomingForegroundAcceptanceAuthorizerSpy(decision: .authorized)
        let acceptanceGate = DisabledNativeIncomingForegroundAcceptanceGate(isEnabled: true,
                                                                            stateStore: stateStore,
                                                                            diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                                                            authorizer: authorizer)
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)
        let identity = safeIdentity()

        _ = adapter.reportSyntheticIncomingCall(identity: identity, displayLabel: "Pilot Participant")
        reporter.simulateAnswer()
        let blockedBeforeDecision = acceptanceGate.isMediaAllowedAfterForegroundAcceptance(identity: identity)
        let outcome = acceptanceGate.requestForegroundAcceptance(identity: identity)

        #expect(stateStore.state(for: identity.handle) == .foregroundCredentialAuthorized)
        #expect(blockedBeforeDecision == false)
        #expect(outcome == .credentialAuthorized(identity))
        #expect(authorizer.requestedIdentities == [identity])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == true)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundAcceptanceGateBlocksMediaBeforeAuthorityAllows() {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let authorizer = NativeIncomingForegroundAcceptanceAuthorizerSpy(decision: .authorized)
        let acceptanceGate = makeAcceptanceGate(stateStore: stateStore,
                                                diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                                authorizer: authorizer)
        let identity = answerRequestedIdentity(stateStore: stateStore)

        #expect(stateStore.state(for: identity.handle) == .answerRequested)
        #expect(acceptanceGate.isMediaAllowedAfterForegroundAcceptance(identity: identity) == false)
        #expect(authorizer.requestedIdentities.isEmpty)
    }

    @Test
    func foregroundAcceptanceGateFailsClosedWithoutAuthority() {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let acceptanceGate = makeAcceptanceGate(stateStore: stateStore,
                                                diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                                authorizer: nil)
        let identity = answerRequestedIdentity(stateStore: stateStore)

        let outcome = acceptanceGate.requestForegroundAcceptance(identity: identity)

        #expect(outcome == .failClosed(.foregroundCredentialAuthorityUnavailable))
        #expect(stateStore.state(for: identity.handle) == .failed)
        #expect(acceptanceGate.isMediaAllowedAfterForegroundAcceptance(identity: identity) == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.failClosedReason == .foregroundCredentialAuthorityUnavailable)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundAcceptanceGateFailsClosedForDeniedMalformedExpiredAndUnverifiableAuthority() {
        let cases: [(NativeIncomingForegroundAcceptanceDecision, NativeIncomingCallFailClosedReason)] = [
            (.denied, .foregroundCredentialDenied),
            (.malformed, .foregroundCredentialMalformed),
            (.expired, .foregroundCredentialExpired),
            (.unverifiable, .foregroundCredentialUnverifiable)
        ]

        for (index, testCase) in cases.enumerated() {
            let dependencies = makeDependencies()
            let stateStore = NativeIncomingCallUIProofStateStoreSpy()
            let authorizer = NativeIncomingForegroundAcceptanceAuthorizerSpy(decision: testCase.0)
            let acceptanceGate = makeAcceptanceGate(stateStore: stateStore,
                                                    diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                                    authorizer: authorizer)
            let identity = answerRequestedIdentity(stateStore: stateStore,
                                                   handle: "safe-local-call-\(index)")

            let outcome = acceptanceGate.requestForegroundAcceptance(identity: identity)

            #expect(outcome == .failClosed(testCase.1))
            #expect(authorizer.requestedIdentities == [identity])
            #expect(stateStore.state(for: identity.handle) == .failed)
            #expect(acceptanceGate.isMediaAllowedAfterForegroundAcceptance(identity: identity) == false)
            #expect(dependencies.diagnosticsRecorder.diagnostics.last?.failClosedReason == testCase.1)
            #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == true)
            #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
        }
    }

    @Test
    func foregroundAcceptanceGateAuthorizesOnlySafeLocalStateWithoutConnectingMedia() {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let authorizer = NativeIncomingForegroundAcceptanceAuthorizerSpy(decision: .authorized)
        let acceptanceGate = makeAcceptanceGate(stateStore: stateStore,
                                                diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                                authorizer: authorizer)
        let identity = answerRequestedIdentity(stateStore: stateStore)

        let outcome = acceptanceGate.requestForegroundAcceptance(identity: identity)

        #expect(outcome == .credentialAuthorized(identity))
        #expect(authorizer.requestedIdentities == [identity])
        #expect(stateStore.state(for: identity.handle) == .foregroundCredentialAuthorized)
        #expect(acceptanceGate.isMediaAllowedAfterForegroundAcceptance(identity: identity) == true)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.lifecycleState == .foregroundCredentialAuthorized)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == true)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundAcceptanceGateRequiresAnswerRequestedState() {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let authorizer = NativeIncomingForegroundAcceptanceAuthorizerSpy(decision: .authorized)
        let acceptanceGate = makeAcceptanceGate(stateStore: stateStore,
                                                diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                                authorizer: authorizer)
        let identity = safeIdentity()
        stateStore.setState(.reported, for: identity.handle)

        let outcome = acceptanceGate.requestForegroundAcceptance(identity: identity)

        #expect(outcome == .failClosed(.unverifiable))
        #expect(authorizer.requestedIdentities.isEmpty)
        #expect(stateStore.state(for: identity.handle) == .failed)
        #expect(acceptanceGate.isMediaAllowedAfterForegroundAcceptance(identity: identity) == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundAcceptanceEndClearsLocalState() {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let authorizer = NativeIncomingForegroundAcceptanceAuthorizerSpy(decision: .authorized)
        let acceptanceGate = makeAcceptanceGate(stateStore: stateStore,
                                                diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                                authorizer: authorizer)
        let identity = answerRequestedIdentity(stateStore: stateStore)
        _ = acceptanceGate.requestForegroundAcceptance(identity: identity)

        acceptanceGate.endForegroundAcceptance(identity: identity)

        #expect(stateStore.state(for: identity.handle) == nil)
        #expect(acceptanceGate.isMediaAllowedAfterForegroundAcceptance(identity: identity) == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.lifecycleState == .ended)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundAcceptanceDiagnosticsStayRedactedAndRouteFree() {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let authorizer = NativeIncomingForegroundAcceptanceAuthorizerSpy(decision: .authorized)
        let acceptanceGate = makeAcceptanceGate(stateStore: stateStore,
                                                diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                                authorizer: authorizer)
        let identity = answerRequestedIdentity(stateStore: stateStore)
        _ = acceptanceGate.requestForegroundAcceptance(identity: identity)

        let description = String(describing: acceptanceGate)
            + " " + String(describing: authorizer)
            + " " + dependencies.diagnosticsRecorder.diagnostics.map(String.init(describing:)).joined(separator: " ")

        #expect(description.contains("realRuntime: false"))
        #expect(Self.forbiddenFragments.allSatisfy { !description.contains($0) })
        #expect(!description.contains("emitSignal"))
        #expect(!description.contains("displayCall"))
        #expect(!description.contains("presentCallScreen"))
    }

    @Test
    func endCallbackClearsLocalSyntheticState() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)
        let identity = safeIdentity()
        _ = adapter.reportSyntheticIncomingCall(identity: identity, displayLabel: "Pilot Participant")

        reporter.simulateEnd()
        let secondEnd = adapter.endSyntheticCall(handle: "safe-local-call")

        #expect(actionHandler.endedIdentities == [identity])
        #expect(secondEnd == .failed(.unverifiable))
        #expect(eventRecorder.events == [.reported, .ended, .failed(.unverifiable)])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last == .failClosed(.unverifiable))
    }

    @Test
    func muteCallbackIsDiagnosticOnly() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)
        let identity = safeIdentity()
        _ = adapter.reportSyntheticIncomingCall(identity: identity, displayLabel: "Pilot Participant")

        reporter.simulateMute(true)

        #expect(actionHandler.muteActions == [true])
        #expect(actionHandler.mutedIdentities == [identity])
        #expect(eventRecorder.events == [.reported, .muted(true)])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func unknownHandleFailsClosed() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)

        let result = adapter.endSyntheticCall(handle: "unknown-local-call")

        #expect(result == .failed(.unverifiable))
        #expect(actionHandler.endedIdentities.isEmpty)
        #expect(eventRecorder.events == [.failed(.unverifiable)])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last == .failClosed(.unverifiable))
    }

    @Test
    func diagnosticsStayRedacted() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)
        _ = adapter.reportSyntheticIncomingCall(identity: safeIdentity(), displayLabel: "Pilot Participant")
        reporter.simulateAnswer()

        let description = String(describing: adapter)
            + " " + String(describing: reporter)
            + " " + eventRecorder.description
            + " " + dependencies.diagnosticsRecorder.diagnostics.map(String.init(describing:)).joined(separator: " ")

        #expect(description.contains("activeCallCount"))
        #expect(Self.forbiddenFragments.allSatisfy { !description.contains($0) })
        #expect(!description.contains("displayCall"))
        #expect(!description.contains("presentCallScreen"))
    }

    private static let forbiddenFragments = [
        "!unsafe-room",
        "@unsafe-user",
        "DEVICE-PRIVATE",
        "redacted-fixture",
        "sample-media-value",
        "displayCall",
        "presentCallScreen"
    ]

    private func safeIdentity(handle rawHandle: String = "safe-local-call") -> NativeIncomingCallIdentity {
        guard let handle = NativeIncomingCallHandle(rawHandle) else {
            fatalError("Expected safe local handle.")
        }

        return NativeIncomingCallIdentity(handle: handle, receivedAt: Date())
    }

    private func answerRequestedIdentity(stateStore: NativeIncomingCallUIProofStateStoreSpy,
                                         handle: String = "safe-local-call") -> NativeIncomingCallIdentity {
        let identity = safeIdentity(handle: handle)
        stateStore.setState(.answerRequested, for: identity.handle)
        return identity
    }

    private func makeDependencies() -> NativeIncomingSyntheticCallKitUIProofDependencies {
        .init(diagnosticsRecorder: NativeIncomingCallDiagnosticsRecorderSpy())
    }

    private func makeAcceptanceGate(stateStore: NativeIncomingCallUIProofStateStoreSpy,
                                    diagnosticsRecorder: NativeIncomingCallDiagnosticsRecorderSpy,
                                    authorizer: NativeIncomingForegroundAcceptanceAuthorizing?) -> DisabledNativeIncomingForegroundAcceptanceGate {
        DisabledNativeIncomingForegroundAcceptanceGate(isEnabled: true,
                                                       stateStore: stateStore,
                                                       diagnosticsRecorder: diagnosticsRecorder,
                                                       authorizer: authorizer)
    }

    private func makeAdapter(reporter: NativeIncomingSyntheticCallKitUIReporterSpy,
                             actionHandler: NativeIncomingSyntheticCallKitActionHandling,
                             diagnosticsRecorder: NativeIncomingCallDiagnosticsRecorderSpy,
                             eventRecorder: NativeIncomingSyntheticCallKitUIProofEventRecorderSpy) -> NativeIncomingSyntheticCallKitUIProofAdapter {
        NativeIncomingSyntheticCallKitUIProofAdapter(isEnabled: true,
                                                     reporter: reporter,
                                                     actionHandler: actionHandler,
                                                     diagnosticsRecorder: diagnosticsRecorder,
                                                     eventRecorder: eventRecorder)
    }
}

private final class NativeIncomingCallUIProofStateStoreSpy: NativeIncomingCallStateStoring {
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

private struct NativeIncomingSyntheticCallKitUIProofDependencies {
    let diagnosticsRecorder: NativeIncomingCallDiagnosticsRecorderSpy
}

private final class NativeIncomingCallDiagnosticsRecorderSpy: NativeIncomingCallDiagnosticsRecording {
    private(set) var diagnostics = [NativeIncomingCallRedactedDiagnostics]()

    func record(_ diagnostics: NativeIncomingCallRedactedDiagnostics) {
        self.diagnostics.append(diagnostics)
    }
}

private final class NativeIncomingForegroundAcceptanceAuthorizerSpy: NativeIncomingForegroundAcceptanceAuthorizing, CustomStringConvertible, CustomDebugStringConvertible {
    private let decision: NativeIncomingForegroundAcceptanceDecision
    private(set) var requestedIdentities = [NativeIncomingCallIdentity]()

    init(decision: NativeIncomingForegroundAcceptanceDecision) {
        self.decision = decision
    }

    func foregroundAcceptanceDecision(for identity: NativeIncomingCallIdentity) -> NativeIncomingForegroundAcceptanceDecision {
        requestedIdentities.append(identity)
        return decision
    }

    var description: String {
        "NativeIncomingForegroundAcceptanceAuthorizerSpy(requestCount: \(requestedIdentities.count), decision: \(decision))"
    }

    var debugDescription: String {
        description
    }
}

private final class NativeIncomingSyntheticCallKitActionHandlerSpy: NativeIncomingSyntheticCallKitActionHandling, CustomStringConvertible {
    private(set) var answeredIdentities = [NativeIncomingCallIdentity]()
    private(set) var endedIdentities = [NativeIncomingCallIdentity]()
    private(set) var mutedIdentities = [NativeIncomingCallIdentity]()
    private(set) var muteActions = [Bool]()

    func answerSyntheticCall(identity: NativeIncomingCallIdentity) {
        answeredIdentities.append(identity)
    }

    func endSyntheticCall(identity: NativeIncomingCallIdentity) {
        endedIdentities.append(identity)
    }

    func setSyntheticCallMuted(_ isMuted: Bool, identity: NativeIncomingCallIdentity) {
        muteActions.append(isMuted)
        mutedIdentities.append(identity)
    }

    var description: String {
        "NativeIncomingSyntheticCallKitActionHandlerSpy(answeredCount: \(answeredIdentities.count), endedCount: \(endedIdentities.count), mutedCount: \(mutedIdentities.count))"
    }
}

private final class NativeIncomingSyntheticCallKitUIReporterSpy: NativeIncomingSyntheticCallKitUIReporting, CustomStringConvertible {
    weak var delegate: NativeIncomingSyntheticCallKitUIReportingDelegate?

    private(set) var reportedCalls = [UUID]()
    private(set) var endedCalls = [UUID]()
    private var labels = [UUID: NativeIncomingCallKitDisplayMetadata]()

    func reportIncomingCall(callUUID: UUID, displayMetadata: NativeIncomingCallKitDisplayMetadata) -> Bool {
        reportedCalls.append(callUUID)
        labels[callUUID] = displayMetadata
        return true
    }

    func endCall(callUUID: UUID) {
        endedCalls.append(callUUID)
    }

    func simulateAnswer() {
        guard let callUUID = reportedCalls.last else {
            return
        }

        delegate?.syntheticCallKitUIReportingDidAnswer(callUUID: callUUID)
    }

    func simulateEnd() {
        guard let callUUID = reportedCalls.last else {
            return
        }

        delegate?.syntheticCallKitUIReportingDidEnd(callUUID: callUUID)
    }

    func simulateMute(_ isMuted: Bool) {
        guard let callUUID = reportedCalls.last else {
            return
        }

        delegate?.syntheticCallKitUIReportingDidSetMuted(isMuted, callUUID: callUUID)
    }

    var description: String {
        "NativeIncomingSyntheticCallKitUIReporterSpy(reportedCount: \(reportedCalls.count), endedCount: \(endedCalls.count), labelCount: \(labels.count))"
    }
}

private final class NativeIncomingSyntheticCallKitUIProofEventRecorderSpy: NativeIncomingSyntheticCallKitUIProofEventRecording, CustomStringConvertible {
    private(set) var events = [NativeIncomingSyntheticCallKitUIProofEvent]()

    func recordSyntheticCallKitUIProofEvent(_ event: NativeIncomingSyntheticCallKitUIProofEvent) {
        events.append(event)
    }

    var description: String {
        "NativeIncomingSyntheticCallKitUIProofEventRecorderSpy(eventCount: \(events.count))"
    }
}
