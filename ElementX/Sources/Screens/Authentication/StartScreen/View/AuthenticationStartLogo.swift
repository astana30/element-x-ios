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
                    .frame(width: 88, height: 88)
            } else {
                logo
                    .frame(width: 104, height: 104)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 8)
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
