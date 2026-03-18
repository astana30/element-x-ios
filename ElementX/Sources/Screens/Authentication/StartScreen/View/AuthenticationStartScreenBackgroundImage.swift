//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// The background gradient shown on the launch, splash and onboarding screens.
struct AuthenticationStartScreenBackgroundImage: View {
    var body: some View {
        ZStack {
            // Main sky-blue base
            LinearGradient(stops: [
                .init(color: Color(red: 0.55, green: 0.85, blue: 0.98), location: 0.00),
                .init(color: Color(red: 0.35, green: 0.75, blue: 0.95), location: 0.42),
                .init(color: Color(red: 0.18, green: 0.63, blue: 0.89), location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.10, y: 0.08),
            endPoint: UnitPoint(x: 0.92, y: 0.96))

            // Stronger golden glow
            RadialGradient(stops: [
                .init(color: Color(red: 0.98, green: 0.80, blue: 0.26).opacity(0.48), location: 0.00),
                .init(color: Color(red: 0.98, green: 0.80, blue: 0.26).opacity(0.24), location: 0.22),
                .init(color: Color(red: 0.98, green: 0.80, blue: 0.26).opacity(0.10), location: 0.48),
                .init(color: .clear, location: 1.00)
            ],
            center: UnitPoint(x: 0.86, y: 0.18),
            startRadius: 12,
            endRadius: 340)

            // Secondary warm highlight so gold is not too local
            LinearGradient(stops: [
                .init(color: .clear, location: 0.48),
                .init(color: Color(red: 0.98, green: 0.82, blue: 0.40).opacity(0.10), location: 0.72),
                .init(color: Color(red: 0.98, green: 0.82, blue: 0.40).opacity(0.18), location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.30, y: 0.20),
            endPoint: UnitPoint(x: 1.00, y: 1.00))

            // Noticeable white light sweep
            LinearGradient(stops: [
                .init(color: Color.white.opacity(0.28), location: 0.00),
                .init(color: Color.white.opacity(0.14), location: 0.16),
                .init(color: .clear, location: 0.38),
                .init(color: .clear, location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.02, y: 0.00),
            endPoint: UnitPoint(x: 0.62, y: 0.52))

            // Soft white bloom
            RadialGradient(stops: [
                .init(color: Color.white.opacity(0.22), location: 0.00),
                .init(color: Color.white.opacity(0.08), location: 0.26),
                .init(color: .clear, location: 0.62)
            ],
            center: UnitPoint(x: 0.22, y: 0.14),
            startRadius: 8,
            endRadius: 240)

            // Slight depth at the bottom
            LinearGradient(stops: [
                .init(color: .clear, location: 0.62),
                .init(color: Color(red: 0.02, green: 0.28, blue: 0.54).opacity(0.10), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
