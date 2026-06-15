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
    #endif
}
#endif
