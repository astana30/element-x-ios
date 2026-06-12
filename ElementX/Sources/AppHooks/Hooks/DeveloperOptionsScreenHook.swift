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

    var body: some View {
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
    }

    private func refreshReceiverSummary(after delay: Duration? = nil) {
        Task { @MainActor in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            receiverSummary = SalemXForegroundSSESmokeControls.redactedReceiverStateSummary()
        }
    }
}
#endif
