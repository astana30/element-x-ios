//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

protocol DeveloperOptionsScreenHookProtocol {
    func generalSectionRows() -> AnyView?
}

struct DefaultDeveloperOptionsScreenHook: DeveloperOptionsScreenHookProtocol {
    func generalSectionRows() -> AnyView? {
        nil
    }
}

#if DEBUG && canImport(CallKit) && os(iOS)
extension AppHooks {
    func setUp() {
        registerDeveloperOptionsScreenHook(SalemXDeveloperOptionsScreenHook())
        #if canImport(PushKit)
        SalemXPushKitRegistrationSmokeDebugBridge.recordSenderDebugBuildLaunchMarker()
        #endif
    }
}

struct SalemXDeveloperOptionsScreenHook: DeveloperOptionsScreenHookProtocol {
    func generalSectionRows() -> AnyView? {
        AnyView(SalemXForegroundSSESmokeControlsView())
    }
}

enum SalemXForegroundSSESmokeControls {
    static let receiverStreamURLString = "https://matrix.mertis.kz/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/stream"
    static let pushKitTokenUploadURLString = "https://matrix.mertis.kz/_matrix/client/unstable/kz.salemx.direct_call/pushkit/token"
    static let expectedReceiverUserHash = "497015f5745c933a"

    static func startReceiverSSE() {
        SalemXForegroundSSEReceiverSmokeDebugBridge.configureWithCurrentSessionStreamURLString(receiverStreamURLString)
    }

    static func stopReceiverSSE() {
        SalemXForegroundSSEReceiverSmokeDebugBridge.stop()
    }

    static func redactedReceiverStateSummary() -> String {
        SalemXForegroundSSEReceiverSmokeDebugBridge.redactedStateSummary()
    }
}

private struct SalemXForegroundSSESmokeControlsView: View {
    @State private var receiverSummary = SalemXForegroundSSESmokeControls.redactedReceiverStateSummary()
    #if canImport(PushKit)
    @State private var pushKitSummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedStateSummary()
    @State private var pushKitUploadSummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedUploadStateSummary()
    @State private var matrixSessionWhoamiSummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedMatrixSessionWhoamiSummary()
    @State private var voIPReceiptSummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedVoIPPushReceiptSummary()
    @State private var localCallKitOnlySummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedLocalCallKitOnlySummary()
    @State private var localBackgroundCallKitOnlySummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedLocalBackgroundCallKitOnlySummary()
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup("Foreground SSE smoke") {
                Button("Start receiver SSE") {
                    SalemXForegroundSSESmokeControls.startReceiverSSE()
                    refreshReceiverSummary(after: .milliseconds(600))
                }

                Button("Refresh receiver proof") {
                    refreshReceiverSummary()
                }

                Button("Stop receiver SSE", role: .destructive) {
                    SalemXForegroundSSESmokeControls.stopReceiverSSE()
                    refreshReceiverSummary()
                }

                Text(receiverSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("foregroundSSESmokeReceiverProof")
            }

            #if canImport(PushKit)
            DisclosureGroup("PushKit registration smoke") {
                Button("Start PushKit registration smoke") {
                    pushKitSummary = SalemXPushKitRegistrationSmokeDebugBridge.startRegistrationSmoke()
                    refreshPushKitSummary(after: .seconds(2))
                }

                Button("Refresh PushKit proof") {
                    refreshPushKitSummary()
                }

                Text(pushKitSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("pushKitRegistrationSmokeProof")

                Button("Start PushKit token upload smoke") {
                    pushKitUploadSummary = SalemXPushKitRegistrationSmokeDebugBridge.startRegistrationUploadSmokeWithCurrentSessionURLString(SalemXForegroundSSESmokeControls.pushKitTokenUploadURLString)
                    refreshPushKitUploadSummary(after: .seconds(5))
                }

                Button("Refresh PushKit upload proof") {
                    refreshPushKitUploadSummary()
                }

                Text(pushKitUploadSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("pushKitTokenUploadSmokeProof")

                Button("Start Matrix session whoami smoke") {
                    matrixSessionWhoamiSummary = SalemXPushKitRegistrationSmokeDebugBridge.startMatrixSessionWhoamiSmokeWithExpectedUserHash(SalemXForegroundSSESmokeControls.expectedReceiverUserHash)
                    refreshMatrixSessionWhoamiSummary(after: .seconds(3))
                }

                Button("Refresh Matrix session whoami proof") {
                    refreshMatrixSessionWhoamiSummary()
                }

                Text(matrixSessionWhoamiSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("matrixSessionWhoamiSmokeProof")

                Button("Prepare Answer marker: lock screen") {
                    voIPReceiptSummary = SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitOperatorReadyToAnswer("lockscreen")
                }

                Button("Prepare Answer marker: full screen") {
                    voIPReceiptSummary = SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitOperatorReadyToAnswer("fullscreen")
                }

                Button("Prepare Answer marker: banner") {
                    voIPReceiptSummary = SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitOperatorReadyToAnswer("banner")
                }

                Button("Prepare Answer marker: foreground") {
                    voIPReceiptSummary = SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitOperatorReadyToAnswer("foreground")
                }

                Button("Mark CallKit Answer tap immediate") {
                    voIPReceiptSummary = SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitOperatorAnswerIntent("immediate")
                }

                Button("Mark CallKit Answer tap 1-2s") {
                    voIPReceiptSummary = SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitOperatorAnswerIntent("1-2s")
                }

                Button("Mark CallKit Answer tap >2s") {
                    voIPReceiptSummary = SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitOperatorAnswerIntent(">2s")
                }

                Button("Mark CallKit End intent") {
                    voIPReceiptSummary = SalemXPushKitRegistrationSmokeDebugBridge.recordCallKitOperatorEndIntent("unknown")
                }

                Button("Start local CallKit-only answerability smoke") {
                    localCallKitOnlySummary = SalemXPushKitRegistrationSmokeDebugBridge.startLocalCallKitOnlyAnswerabilitySmoke()
                    refreshLocalCallKitOnlySummary(after: .seconds(1))
                }

                Button("Refresh local CallKit-only proof") {
                    refreshLocalCallKitOnlySummary()
                }

                Button("Schedule local background CallKit-only smoke in 5s") {
                    localBackgroundCallKitOnlySummary = SalemXPushKitRegistrationSmokeDebugBridge.scheduleLocalBackgroundCallKitOnlyAnswerabilitySmoke()
                    refreshLocalBackgroundCallKitOnlySummary(after: .seconds(7))
                }

                Button("Refresh local background CallKit-only proof") {
                    refreshLocalBackgroundCallKitOnlySummary()
                }

                Button("Refresh VoIP receipt proof") {
                    refreshVoIPReceiptSummary()
                }

                Text(voIPReceiptSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("voIPPushReceiptProof")

                Text(localCallKitOnlySummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("localCallKitOnlyProof")

                Text(localBackgroundCallKitOnlySummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("localBackgroundCallKitOnlyProof")
            }
            #endif
        }
    }

    private func refreshReceiverSummary(after delay: Duration? = nil) {
        Task { @MainActor in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            receiverSummary = SalemXForegroundSSESmokeControls.redactedReceiverStateSummary()
        }
    }

    #if canImport(PushKit)
    private func refreshPushKitSummary(after delay: Duration? = nil) {
        Task { @MainActor in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            pushKitSummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedStateSummary()
        }
    }

    private func refreshPushKitUploadSummary(after delay: Duration? = nil) {
        Task { @MainActor in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            pushKitUploadSummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedUploadStateSummary()
        }
    }

    private func refreshMatrixSessionWhoamiSummary(after delay: Duration? = nil) {
        Task { @MainActor in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            matrixSessionWhoamiSummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedMatrixSessionWhoamiSummary()
        }
    }

    private func refreshVoIPReceiptSummary(after delay: Duration? = nil) {
        Task { @MainActor in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            voIPReceiptSummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedVoIPPushReceiptSummary()
        }
    }

    private func refreshLocalCallKitOnlySummary(after delay: Duration? = nil) {
        Task { @MainActor in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            localCallKitOnlySummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedLocalCallKitOnlySummary()
        }
    }

    private func refreshLocalBackgroundCallKitOnlySummary(after delay: Duration? = nil) {
        Task { @MainActor in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            localBackgroundCallKitOnlySummary = SalemXPushKitRegistrationSmokeDebugBridge.redactedLocalBackgroundCallKitOnlySummary()
        }
    }
    #endif
}
#endif
