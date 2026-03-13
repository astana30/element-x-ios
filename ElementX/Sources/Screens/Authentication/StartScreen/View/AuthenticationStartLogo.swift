//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// The app's logo styled to fit on various launch pages.
struct AuthenticationStartLogo: View {
    let hideBrandChrome: Bool

    var body: some View {
        Group {
            if hideBrandChrome {
                logo
                    .frame(width: 96, height: 96)
            } else {
                logo
                    .frame(width: 112, height: 112)
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }

    private var logo: some View {
        Image("salemx_welcome_logo")
            .resizable()
            .scaledToFit()
    }
}
