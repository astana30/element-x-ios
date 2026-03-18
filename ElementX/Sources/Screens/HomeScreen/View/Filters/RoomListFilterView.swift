//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct RoomListFilterView: View {
    let filter: RoomListFilter
    @Binding var isActive: Bool

    var body: some View {
        Toggle(isOn: $isActive) {
            Text(filter.localizedName)
        }
        .toggleStyle(FilterToggleStyle())
    }
}

private struct FilterToggleStyle: ToggleStyle {
    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    private func background(isOn: Bool) -> some ShapeStyle {
        if isOn {
            return AnyShapeStyle(LinearGradient(stops: [
                    .init(color: Color(red: 0.43, green: 0.76, blue: 0.98), location: 0.00),
                    .init(color: Color(red: 0.17, green: 0.57, blue: 0.91), location: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing))
        } else {
            return AnyShapeStyle(Color(red: 0.97, green: 0.98, blue: 0.995))
        }
    }

    private func strokeColor(isOn: Bool) -> Color {
        isOn
            ? Color(red: 0.20, green: 0.55, blue: 0.88).opacity(0.28)
            : Color(red: 0.82, green: 0.87, blue: 0.93)
    }

    private func foregroundColor(isOn: Bool) -> Color {
        isOn ? .white : Color(red: 0.22, green: 0.29, blue: 0.38)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.compound.bodyMDSemibold)
            .foregroundColor(foregroundColor(isOn: configuration.isOn))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background {
                shape
                    .fill(background(isOn: configuration.isOn))
                    .overlay {
                        shape.stroke(strokeColor(isOn: configuration.isOn), lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        shape
                            .fill(LinearGradient(stops: [
                                    .init(color: Color.white.opacity(configuration.isOn ? 0.22 : 0.55), location: 0.00),
                                    .init(color: Color.white.opacity(configuration.isOn ? 0.06 : 0.18), location: 0.28),
                                    .init(color: .clear, location: 0.65)
                                ],
                                startPoint: .top,
                                endPoint: .bottom))
                    }
                    .shadow(color: configuration.isOn
                        ? Color(red: 0.18, green: 0.52, blue: 0.86).opacity(0.18)
                        : Color.black.opacity(0.04),
                        radius: configuration.isOn ? 10 : 4,
                        x: 0,
                        y: configuration.isOn ? 5 : 2)
            }
            .scaleEffect(configuration.isOn ? 1.0 : 0.985)
            .contentShape(shape)
            .onTapGesture {
                configuration.isOn.toggle()
            }
    }
}

// MARK: - Previews

struct RoomListFilterView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 12) {
            RoomListFilterView(filter: .people, isActive: .constant(false))
            RoomListFilterView(filter: .people, isActive: .constant(true))
        }
        .padding()
    }
}
