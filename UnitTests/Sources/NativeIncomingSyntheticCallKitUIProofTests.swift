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

    private func safeIdentity() -> NativeIncomingCallIdentity {
        guard let handle = NativeIncomingCallHandle("safe-local-call") else {
            fatalError("Expected safe local handle.")
        }

        return NativeIncomingCallIdentity(handle: handle, receivedAt: Date())
    }

    private func makeDependencies() -> NativeIncomingSyntheticCallKitUIProofDependencies {
        .init(diagnosticsRecorder: NativeIncomingCallDiagnosticsRecorderSpy())
    }

    private func makeAdapter(reporter: NativeIncomingSyntheticCallKitUIReporterSpy,
                             actionHandler: NativeIncomingSyntheticCallKitActionHandlerSpy,
                             diagnosticsRecorder: NativeIncomingCallDiagnosticsRecorderSpy,
                             eventRecorder: NativeIncomingSyntheticCallKitUIProofEventRecorderSpy) -> NativeIncomingSyntheticCallKitUIProofAdapter {
        NativeIncomingSyntheticCallKitUIProofAdapter(isEnabled: true,
                                                     reporter: reporter,
                                                     actionHandler: actionHandler,
                                                     diagnosticsRecorder: diagnosticsRecorder,
                                                     eventRecorder: eventRecorder)
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
