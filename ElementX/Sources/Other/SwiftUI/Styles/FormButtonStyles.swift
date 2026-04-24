//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// Small squared action button style for settings screens
struct FormActionButtonStyle: ButtonStyle {
    let title: String
    
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.label
                .buttonStyle(.plain)
                .foregroundColor(.compound.iconSecondary)
                .scaledFrame(size: 24)
            
            Text(title)
                .foregroundColor(.compound.textPrimary)
                .font(.compound.bodyLG)
                .textCase(.none)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(configuration.isPressed ? Color.compound.bgSubtlePrimary : .compound.bgCanvasDefaultLevel1)
        }
    }
}

struct FormButtonStyles_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        Form {
            Section { } header: {
                Button { } label: {
                    CompoundIcon(\.shareIos)
                }
                .buttonStyle(FormActionButtonStyle(title: "Share"))
            }
        }
        .compoundList()
    }
}

enum SalemBrandPalette {
    static let primary = Color(red: 0.05, green: 0.49, blue: 0.85)
    static let primaryStrong = Color(red: 0.03, green: 0.37, blue: 0.69)
    static let glow = Color(red: 0.07, green: 0.67, blue: 0.90)
    static let sky = Color(red: 0.27, green: 0.70, blue: 0.98)
    static let skyLight = Color(red: 0.60, green: 0.86, blue: 1.00)
    static let warm = Color(red: 0.95, green: 0.66, blue: 0.22)

    static let card = Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.08)
    static let cardHighlighted = Color(red: 0.03, green: 0.38, blue: 0.69).opacity(0.16)
    static let cardBorder = Color(red: 0.11, green: 0.40, blue: 0.69).opacity(0.22)
    static let cardBorderHighlighted = Color(red: 0.07, green: 0.67, blue: 0.90).opacity(0.55)
}

private struct SalemScreenBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Color.compound.bgCanvasDefault
                        .ignoresSafeArea()

                    LinearGradient(colors: [SalemBrandPalette.primary.opacity(0.20),
                                            SalemBrandPalette.glow.opacity(0.08),
                                            .clear],
                                   startPoint: .topLeading,
                                   endPoint: .center)
                        .ignoresSafeArea()

                    RadialGradient(colors: [SalemBrandPalette.warm.opacity(0.12), .clear],
                                   center: .topTrailing,
                                   startRadius: 10,
                                   endRadius: 260)
                        .ignoresSafeArea()
                }
            }
    }
}

private struct SalemCardModifier: ViewModifier {
    let highlighted: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        content
            .background {
                shape
                    .fill(highlighted ? SalemBrandPalette.cardHighlighted : SalemBrandPalette.card)
                    .overlay {
                        shape.stroke(highlighted ? SalemBrandPalette.cardBorderHighlighted : SalemBrandPalette.cardBorder, lineWidth: highlighted ? 1.5 : 1)
                    }
            }
    }
}

extension View {
    func salemScreenBackground() -> some View {
        modifier(SalemScreenBackgroundModifier())
    }

    func salemCard(highlighted: Bool = false) -> some View {
        modifier(SalemCardModifier(highlighted: highlighted))
    }
}
