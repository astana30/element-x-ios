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
        #expect(eventRecorder.events == [.reported, .answerActionDelivered(uuidMatched: true), .answered, .ended])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func reportRetainsProviderDelegateAndActiveCallUntilAnswer() {
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
        let retentionProof = adapter.answerRetentionProof(handle: identity.handle.value)

        #expect(retentionProof.providerRetainedForAnswer)
        #expect(retentionProof.delegateRetainedForAnswer)
        #expect(retentionProof.activeCallUUIDRetained)

        reporter.simulateAnswer()
        let postAnswerRetentionProof = adapter.answerRetentionProof(handle: identity.handle.value)

        #expect(postAnswerRetentionProof.providerRetainedForAnswer)
        #expect(postAnswerRetentionProof.delegateRetainedForAnswer)
        #expect(!postAnswerRetentionProof.activeCallUUIDRetained)
        #expect(eventRecorder.events == [.reported, .answerActionDelivered(uuidMatched: true), .answered, .ended])
    }

    @Test
    func pendingReportRetainsProviderDelegateAndActiveCallWithoutAnswerBypass() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy(autoCompleteReport: false)
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)
        let identity = safeIdentity()

        let result = adapter.reportSyntheticIncomingCall(identity: identity, displayLabel: "Pilot Participant")
        let retentionProof = adapter.answerRetentionProof(handle: identity.handle.value)

        #expect(result == .reported)
        #expect(reporter.pendingReportCompletionCount == 1)
        #expect(retentionProof.providerRetainedForAnswer)
        #expect(retentionProof.delegateRetainedForAnswer)
        #expect(retentionProof.activeCallUUIDRetained)
        #expect(actionHandler.answeredIdentities.isEmpty)
        #expect(eventRecorder.events.isEmpty)
        #expect(dependencies.diagnosticsRecorder.diagnostics.isEmpty)
    }

    @Test
    func pendingReportCompletionSuccessRecordsReportedWithoutMediaSideEffects() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy(autoCompleteReport: false)
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)

        _ = adapter.reportSyntheticIncomingCall(identity: safeIdentity(), displayLabel: "Pilot Participant")
        reporter.completePendingReport(succeeded: true)

        #expect(eventRecorder.events == [.reported])
        #expect(actionHandler.answeredIdentities.isEmpty)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.lifecycleState == .reported)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func pendingReportCompletionFailureClassifiesFailureWithoutMediaSideEffects() {
        let dependencies = makeDependencies()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy(autoCompleteReport: false)
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let eventRecorder = NativeIncomingSyntheticCallKitUIProofEventRecorderSpy()
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler,
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: eventRecorder)

        _ = adapter.reportSyntheticIncomingCall(identity: safeIdentity(), displayLabel: "Pilot Participant")
        reporter.completePendingReport(succeeded: false)

        #expect(eventRecorder.events == [.failed(.callReportingUnavailable)])
        #expect(actionHandler.answeredIdentities.isEmpty)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.failClosedReason == .callReportingUnavailable)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func resetEndAndAudioSessionCallbacksAreRecordedRedacted() {
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
        reporter.simulateAudioSessionActivated()
        reporter.simulateEnd()
        reporter.simulateReset()
        reporter.simulateAudioSessionDeactivated()

        #expect(actionHandler.endedIdentities == [identity])
        #expect(eventRecorder.events == [
            .reported,
            .audioSessionActivated,
            .endActionDelivered(uuidMatched: true),
            .ended,
            .endActionFulfilled(uuidMatched: true),
            .providerDidReset,
            .audioSessionDeactivated
        ])
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
        #expect(eventRecorder.events == [.reported, .answerActionDelivered(uuidMatched: true), .answered, .ended])
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
    func foregroundNativeIncomingE2ECreatesStateAndRequestsCallKitForForegroundIncomingOnly() {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let e2e = makeForegroundE2E(dependencies: dependencies,
                                    stateStore: stateStore,
                                    reporter: reporter)
        let incomingSession = makeIncomingSession()
        let outgoingSession = makeIncomingSession(direction: .outgoing)
        let connectingSession = makeIncomingSession(state: .connecting)

        let reported = e2e.receiveForegroundIncomingCall(session: incomingSession,
                                                         displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))
        let outgoingRejected = e2e.receiveForegroundIncomingCall(session: outgoingSession,
                                                                 displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))
        let connectingRejected = e2e.receiveForegroundIncomingCall(session: connectingSession,
                                                                   displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))

        guard case .callKitReported(let identity) = reported else {
            Issue.record("Expected foreground incoming session to report through CallKit path.")
            return
        }
        #expect(stateStore.state(for: identity.handle) == .reported)
        #expect(reporter.reportedCalls.count == 1)
        #expect(outgoingRejected == .failClosed(.unverifiable))
        #expect(connectingRejected == .failClosed(.unverifiable))
        #expect(reporter.reportedCalls.count == 1)
    }

    @Test
    func foregroundNativeIncomingE2EAnswerRequiresAcceptanceBeforeMediaConnect() {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let mediaConnector = NativeForegroundIncomingMediaConnectorSpy(outcome: .connected)
        let e2e = makeForegroundE2E(dependencies: dependencies,
                                    stateStore: stateStore,
                                    reporter: reporter,
                                    mediaConnector: mediaConnector)

        let identity = receiveForegroundIncomingCall(e2e: e2e, stateStore: stateStore)
        reporter.simulateAnswer()

        #expect(stateStore.state(for: identity.handle) == .answerRequested)
        #expect(mediaConnector.connectedIdentities.isEmpty)
        #expect(dependencies.diagnosticsRecorder.diagnostics.contains { diagnostics in
            diagnostics.lifecycleState == .answerRequested &&
                diagnostics.mediaCredentialRequested == false &&
                diagnostics.mediaConnectAttempted == false
        })
    }

    @Test
    func foregroundNativeIncomingE2EBlocksMediaForMissingAuthority() async {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let mediaConnector = NativeForegroundIncomingMediaConnectorSpy(outcome: .connected)
        let e2e = makeForegroundE2E(dependencies: dependencies,
                                    stateStore: stateStore,
                                    reporter: reporter,
                                    authorizer: nil,
                                    mediaConnector: mediaConnector)
        let identity = receiveForegroundIncomingCall(e2e: e2e, stateStore: stateStore)
        reporter.simulateAnswer()

        let outcome = await e2e.connectAnsweredForegroundIncomingCall(handle: identity.handle.value)

        #expect(outcome == .failClosed(.foregroundCredentialAuthorityUnavailable))
        #expect(stateStore.state(for: identity.handle) == .failed)
        #expect(mediaConnector.connectedIdentities.isEmpty)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundNativeIncomingE2EBlocksMediaForDeniedMalformedExpiredAndUnverifiableAuthority() async {
        let cases: [(NativeIncomingForegroundAcceptanceDecision, NativeIncomingCallFailClosedReason)] = [
            (.denied, .foregroundCredentialDenied),
            (.malformed, .foregroundCredentialMalformed),
            (.expired, .foregroundCredentialExpired),
            (.unverifiable, .foregroundCredentialUnverifiable)
        ]

        for (index, testCase) in cases.enumerated() {
            let dependencies = makeDependencies()
            let stateStore = NativeIncomingCallUIProofStateStoreSpy()
            let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
            let mediaConnector = NativeForegroundIncomingMediaConnectorSpy(outcome: .connected)
            let e2e = makeForegroundE2E(dependencies: dependencies,
                                        stateStore: stateStore,
                                        reporter: reporter,
                                        authorizer: NativeIncomingForegroundAcceptanceAuthorizerSpy(decision: testCase.0),
                                        mediaConnector: mediaConnector)
            let identity = receiveForegroundIncomingCall(e2e: e2e,
                                                         stateStore: stateStore,
                                                         callID: "call-\(index)")
            reporter.simulateAnswer()

            let outcome = await e2e.connectAnsweredForegroundIncomingCall(handle: identity.handle.value)

            #expect(outcome == .failClosed(testCase.1))
            #expect(stateStore.state(for: identity.handle) == .failed)
            #expect(mediaConnector.connectedIdentities.isEmpty)
            #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == true)
            #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
        }
    }

    @Test
    func foregroundNativeIncomingE2EAuthorizedAuthorityAllowsMediaConnectOnlyAfterApproval() async {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let mediaConnector = NativeForegroundIncomingMediaConnectorSpy(outcome: .connected)
        let e2e = makeForegroundE2E(dependencies: dependencies,
                                    stateStore: stateStore,
                                    reporter: reporter,
                                    mediaConnector: mediaConnector)
        let identity = receiveForegroundIncomingCall(e2e: e2e, stateStore: stateStore)

        #expect(mediaConnector.connectedIdentities.isEmpty)
        reporter.simulateAnswer()
        let outcome = await e2e.connectAnsweredForegroundIncomingCall(handle: identity.handle.value)

        #expect(outcome == .mediaConnected(identity))
        #expect(stateStore.state(for: identity.handle) == .active)
        #expect(mediaConnector.connectedIdentities == [identity])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.lifecycleState == .active)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == true)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == true)
    }

    @Test
    func foregroundNativeIncomingE2EDuplicateAnswerDoesNotCreateDuplicateMediaConnection() async {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let mediaConnector = NativeForegroundIncomingMediaConnectorSpy(outcome: .connected)
        let e2e = makeForegroundE2E(dependencies: dependencies,
                                    stateStore: stateStore,
                                    reporter: reporter,
                                    mediaConnector: mediaConnector)
        let identity = receiveForegroundIncomingCall(e2e: e2e, stateStore: stateStore)
        reporter.simulateAnswer()

        let firstOutcome = await e2e.connectAnsweredForegroundIncomingCall(handle: identity.handle.value)
        let duplicateOutcome = await e2e.connectAnsweredForegroundIncomingCall(handle: identity.handle.value)

        #expect(firstOutcome == .mediaConnected(identity))
        #expect(duplicateOutcome == .mediaConnected(identity))
        #expect(stateStore.state(for: identity.handle) == .active)
        #expect(mediaConnector.connectedIdentities == [identity])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.lifecycleState == .active)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == true)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundNativeIncomingE2EMediaFailureFailsClosedAfterAuthorityApproval() async {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let mediaConnector = NativeForegroundIncomingMediaConnectorSpy(outcome: .failClosed(.mediaSetupUnavailable))
        let e2e = makeForegroundE2E(dependencies: dependencies,
                                    stateStore: stateStore,
                                    reporter: reporter,
                                    mediaConnector: mediaConnector)
        let identity = receiveForegroundIncomingCall(e2e: e2e, stateStore: stateStore)
        reporter.simulateAnswer()

        let outcome = await e2e.connectAnsweredForegroundIncomingCall(handle: identity.handle.value)

        #expect(outcome == .failClosed(.mediaSetupUnavailable))
        #expect(stateStore.state(for: identity.handle) == .failed)
        #expect(mediaConnector.connectedIdentities == [identity])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == true)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == true)
    }

    @Test
    func foregroundNativeIncomingE2EEndClearsStateAndTearsDownStartedMedia() async {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let mediaConnector = NativeForegroundIncomingMediaConnectorSpy(outcome: .connected)
        let e2e = makeForegroundE2E(dependencies: dependencies,
                                    stateStore: stateStore,
                                    reporter: reporter,
                                    mediaConnector: mediaConnector)
        let identity = receiveForegroundIncomingCall(e2e: e2e, stateStore: stateStore)
        reporter.simulateAnswer()
        _ = await e2e.connectAnsweredForegroundIncomingCall(handle: identity.handle.value)

        let outcome = await e2e.endForegroundIncomingCall(handle: identity.handle.value)

        #expect(outcome == .ended)
        #expect(stateStore.state(for: identity.handle) == nil)
        #expect(mediaConnector.endedIdentities == [identity])
        #expect(reporter.endedCalls.count == 1)
    }

    @Test
    func foregroundNativeIncomingE2EEndIsIdempotent() async {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let mediaConnector = NativeForegroundIncomingMediaConnectorSpy(outcome: .connected)
        let e2e = makeForegroundE2E(dependencies: dependencies,
                                    stateStore: stateStore,
                                    reporter: reporter,
                                    mediaConnector: mediaConnector)
        let identity = receiveForegroundIncomingCall(e2e: e2e, stateStore: stateStore)
        reporter.simulateAnswer()
        _ = await e2e.connectAnsweredForegroundIncomingCall(handle: identity.handle.value)

        let firstOutcome = await e2e.endForegroundIncomingCall(handle: identity.handle.value)
        let duplicateOutcome = await e2e.endForegroundIncomingCall(handle: identity.handle.value)

        #expect(firstOutcome == .ended)
        #expect(duplicateOutcome == .ended)
        #expect(stateStore.state(for: identity.handle) == nil)
        #expect(mediaConnector.endedIdentities == [identity])
        #expect(reporter.endedCalls.count == 1)
    }

    @Test
    func foregroundNativeIncomingE2ERepeatedCallsResetLifecycleState() async {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let mediaConnector = NativeForegroundIncomingMediaConnectorSpy(outcome: .connected)
        let e2e = makeForegroundE2E(dependencies: dependencies,
                                    stateStore: stateStore,
                                    reporter: reporter,
                                    mediaConnector: mediaConnector)
        let firstIdentity = receiveForegroundIncomingCall(e2e: e2e,
                                                          stateStore: stateStore,
                                                          callID: "call-a")
        reporter.simulateAnswer()
        _ = await e2e.connectAnsweredForegroundIncomingCall(handle: firstIdentity.handle.value)
        _ = await e2e.endForegroundIncomingCall(handle: firstIdentity.handle.value)

        let secondIdentity = receiveForegroundIncomingCall(e2e: e2e,
                                                           stateStore: stateStore,
                                                           callID: "call-b")
        reporter.simulateAnswer()
        let secondOutcome = await e2e.connectAnsweredForegroundIncomingCall(handle: secondIdentity.handle.value)

        #expect(secondOutcome == .mediaConnected(secondIdentity))
        #expect(stateStore.state(for: firstIdentity.handle) == nil)
        #expect(stateStore.state(for: secondIdentity.handle) == .active)
        #expect(mediaConnector.connectedIdentities == [firstIdentity, secondIdentity])
        #expect(mediaConnector.endedIdentities == [firstIdentity])
    }

    @Test
    func foregroundNativeIncomingE2EMuteRemainsLocalDiagnosticOnly() {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let e2e = makeForegroundE2E(dependencies: dependencies,
                                    stateStore: stateStore,
                                    reporter: reporter,
                                    actionHandler: actionHandler)
        let identity = receiveForegroundIncomingCall(e2e: e2e, stateStore: stateStore)

        let outcome = e2e.setForegroundIncomingCallMuted(true, handle: identity.handle.value)

        #expect(outcome == .muted(true))
        #expect(actionHandler.muteActions == [true])
        #expect(actionHandler.mutedIdentities == [identity])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundNativeIncomingE2EDiagnosticsStayRedactedAndRouteFree() async {
        let dependencies = makeDependencies()
        let stateStore = NativeIncomingCallUIProofStateStoreSpy()
        let reporter = NativeIncomingSyntheticCallKitUIReporterSpy()
        let mediaConnector = NativeForegroundIncomingMediaConnectorSpy(outcome: .connected)
        let e2e = makeForegroundE2E(dependencies: dependencies,
                                    stateStore: stateStore,
                                    reporter: reporter,
                                    mediaConnector: mediaConnector)
        let identity = receiveForegroundIncomingCall(e2e: e2e, stateStore: stateStore)
        reporter.simulateAnswer()
        _ = await e2e.connectAnsweredForegroundIncomingCall(handle: identity.handle.value)

        let description = String(describing: e2e)
            + " " + String(describing: mediaConnector)
            + " " + dependencies.diagnosticsRecorder.diagnostics.map(String.init(describing:)).joined(separator: " ")

        #expect(description.contains("backgroundRuntime: false"))
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
        #expect(eventRecorder.events == [.reported, .endActionDelivered(uuidMatched: true), .ended, .endActionFulfilled(uuidMatched: true), .failed(.unverifiable)])
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

    private func makeForegroundE2E(dependencies: NativeIncomingSyntheticCallKitUIProofDependencies,
                                   stateStore: NativeIncomingCallUIProofStateStoreSpy,
                                   reporter: NativeIncomingSyntheticCallKitUIReporterSpy,
                                   actionHandler: NativeIncomingSyntheticCallKitActionHandling? = nil,
                                   authorizer: NativeIncomingForegroundAcceptanceAuthorizing? = NativeIncomingForegroundAcceptanceAuthorizerSpy(decision: .authorized),
                                   mediaConnector: NativeForegroundIncomingMediaConnectorSpy = .init(outcome: .connected)) -> ForegroundNativeIncomingCallE2ECoordinator {
        let actionRouter = DisabledNativeIncomingCallStateMachineActionRouter(stateStore: stateStore,
                                                                              diagnosticsRecorder: dependencies.diagnosticsRecorder)
        let adapter = makeAdapter(reporter: reporter,
                                  actionHandler: actionHandler ?? NativeIncomingCallStateMachineSyntheticActionHandler(actionRouter: actionRouter),
                                  diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                  eventRecorder: NativeIncomingSyntheticCallKitUIProofEventRecorderSpy())
        let acceptanceGate = makeAcceptanceGate(stateStore: stateStore,
                                                diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                                authorizer: authorizer)
        return ForegroundNativeIncomingCallE2ECoordinator(isEnabled: true,
                                                          stateStore: stateStore,
                                                          callKitAdapter: adapter,
                                                          acceptanceGate: acceptanceGate,
                                                          mediaConnector: mediaConnector,
                                                          diagnosticsRecorder: dependencies.diagnosticsRecorder)
    }

    private func receiveForegroundIncomingCall(e2e: ForegroundNativeIncomingCallE2ECoordinator,
                                               stateStore: NativeIncomingCallUIProofStateStoreSpy,
                                               callID: String = "call-a") -> NativeIncomingCallIdentity {
        let outcome = e2e.receiveForegroundIncomingCall(session: makeIncomingSession(callID: callID),
                                                        displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))
        guard case .callKitReported(let identity) = outcome else {
            fatalError("Expected foreground incoming call to be reported.")
        }
        #expect(stateStore.state(for: identity.handle) == .reported)
        return identity
    }

    private func makeIncomingSession(callID: String = "call-a",
                                     direction: DirectCallDirection = .incoming,
                                     state: DirectCallState = .incomingRinging,
                                     intent: DirectCallIntent = .audio) -> DirectCallSession {
        DirectCallSession(callID: callID,
                          roomID: "safe-room",
                          peerUserID: "safe-peer",
                          direction: direction,
                          intent: intent,
                          encryptionMode: .e2eeRequired,
                          startedAt: Date(),
                          updatedAt: Date(),
                          state: state,
                          encryptionState: .ready)
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

private final class NativeForegroundIncomingMediaConnectorSpy: NativeForegroundIncomingMediaConnecting, CustomStringConvertible, CustomDebugStringConvertible {
    private let outcome: NativeForegroundIncomingMediaConnectionOutcome
    private(set) var connectedIdentities = [NativeIncomingCallIdentity]()
    private(set) var endedIdentities = [NativeIncomingCallIdentity]()

    init(outcome: NativeForegroundIncomingMediaConnectionOutcome) {
        self.outcome = outcome
    }

    func connectForegroundIncomingMedia(identity: NativeIncomingCallIdentity) async -> NativeForegroundIncomingMediaConnectionOutcome {
        connectedIdentities.append(identity)
        return outcome
    }

    func endForegroundIncomingMedia(identity: NativeIncomingCallIdentity) async {
        endedIdentities.append(identity)
    }

    var description: String {
        "NativeForegroundIncomingMediaConnectorSpy(connectCount: \(connectedIdentities.count), endCount: \(endedIdentities.count), outcome: \(outcome))"
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
    var providerRetainedForAnswer = true
    var delegateRetainedForAnswer: Bool {
        delegate != nil
    }

    private let autoCompleteReport: Bool
    private(set) var reportedCalls = [UUID]()
    private(set) var endedCalls = [UUID]()
    private(set) var pendingReportCompletionCount = 0
    private var labels = [UUID: NativeIncomingCallKitDisplayMetadata]()
    private var pendingReportCompletions = [(Bool) -> Void]()

    init(autoCompleteReport: Bool = true) {
        self.autoCompleteReport = autoCompleteReport
    }

    func reportIncomingCall(callUUID: UUID, displayMetadata: NativeIncomingCallKitDisplayMetadata, completion: @escaping (Bool) -> Void) -> Bool {
        reportedCalls.append(callUUID)
        labels[callUUID] = displayMetadata
        if autoCompleteReport {
            completion(true)
        } else {
            pendingReportCompletionCount += 1
            pendingReportCompletions.append(completion)
        }
        return true
    }

    func completePendingReport(succeeded: Bool) {
        guard !pendingReportCompletions.isEmpty else {
            return
        }

        let completion = pendingReportCompletions.removeFirst()
        pendingReportCompletionCount -= 1
        completion(succeeded)
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
        delegate?.syntheticCallKitUIReportingDidFulfillEnd(callUUID: callUUID)
    }

    func simulateReset() {
        delegate?.syntheticCallKitUIReportingDidReset()
    }

    func simulateAudioSessionActivated() {
        delegate?.syntheticCallKitUIReportingDidActivateAudioSession()
    }

    func simulateAudioSessionDeactivated() {
        delegate?.syntheticCallKitUIReportingDidDeactivateAudioSession()
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
