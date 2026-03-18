//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct PlaceholderAvatarImage: View {
    @Environment(\.redactionReasons) private var redactionReasons

    private struct SalemXAvatarStyle {
        let start: Color
        let end: Color
        let text: Color
    }

    private static let styles: [SalemXAvatarStyle] = [
        .init(start: Color(red: 0.90, green: 0.96, blue: 1.00),
              end: Color(red: 0.80, green: 0.91, blue: 0.99),
              text: Color(red: 0.10, green: 0.40, blue: 0.74)),
        .init(start: Color(red: 1.00, green: 0.95, blue: 0.84),
              end: Color(red: 0.98, green: 0.90, blue: 0.73),
              text: Color(red: 0.76, green: 0.57, blue: 0.08)),
        .init(start: Color(red: 0.89, green: 0.97, blue: 0.90),
              end: Color(red: 0.80, green: 0.93, blue: 0.83),
              text: Color(red: 0.18, green: 0.56, blue: 0.28)),
        .init(start: Color(red: 0.97, green: 0.90, blue: 0.88),
              end: Color(red: 0.95, green: 0.83, blue: 0.81),
              text: Color(red: 0.76, green: 0.28, blue: 0.24)),
        .init(start: Color(red: 0.93, green: 0.92, blue: 0.98),
              end: Color(red: 0.88, green: 0.86, blue: 0.96),
              text: Color(red: 0.47, green: 0.22, blue: 0.67)),
        .init(start: Color(red: 0.95, green: 0.92, blue: 0.88),
              end: Color(red: 0.91, green: 0.86, blue: 0.80),
              text: Color(red: 0.53, green: 0.38, blue: 0.20))
    ]

    private let textForImage: String
    private let contentID: String
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                backgroundView
                
                if redactionReasons != .placeholder {
                    Text(textForImage)
                        .foregroundColor(avatarStyle?.text ?? .white)
                        .font(.system(size: geometry.size.width * 0.5625, weight: .semibold))
                        .minimumScaleFactor(0.001)
                        .frame(alignment: .center)
                }
            }
        }
        .aspectRatio(1, contentMode: .fill)
    }

    init(name: String?, contentID: String) {
        let baseName = name ?? contentID.trimmingCharacters(in: .punctuationCharacters)
        textForImage = baseName.first?.uppercased() ?? ""
        self.contentID = contentID
    }

    @ViewBuilder
    private var backgroundView: some View {
        if redactionReasons.contains(.placeholder) {
            Color(.systemGray4)
        } else if let avatarStyle {
            LinearGradient(colors: [avatarStyle.start, avatarStyle.end],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .overlay {
                    LinearGradient(stops: [
                        .init(color: Color.white.opacity(0.18), location: 0.00),
                        .init(color: Color.white.opacity(0.08), location: 0.18),
                        .init(color: Color.clear, location: 0.46)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                }
        } else {
            Color(red: 0.84, green: 0.90, blue: 0.97)
        }
    }
    
    private var avatarStyle: SalemXAvatarStyle? {
        guard !Self.styles.isEmpty else { return nil }
        return Self.styles[avatarStyleIndex]
    }

    private var avatarStyleIndex: Int {
        let scalarSum = contentID.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        return scalarSum % Self.styles.count
    }
}

struct PlaceholderAvatarImage_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 75) {
            PlaceholderAvatarImage(name: "Xavier", contentID: "@userid1:matrix.org")
                .clipShape(Circle())
                .frame(width: 150, height: 100)
            
            PlaceholderAvatarImage(name: "@*~AmazingName~*@", contentID: "@userid2:matrix.org")
                .clipShape(Circle())
                .frame(width: 150, height: 100)
            
            PlaceholderAvatarImage(name: nil, contentID: "@userid3:matrix.org")
                .clipShape(Circle())
                .frame(width: 150, height: 100)
            
            PlaceholderAvatarImage(name: nil, contentID: "@fooserid:matrix.org")
                .clipShape(Circle())
                .frame(width: 30, height: 30)
        }
    }
}
