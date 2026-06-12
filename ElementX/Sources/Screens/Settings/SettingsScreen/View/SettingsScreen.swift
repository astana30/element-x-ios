//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

private struct SettingsTintedIcon: View {
    struct Palette {
        let icon: Color
        let gradientStart: Color
        let gradientEnd: Color
        let glow: Color

        static let amber = Palette(icon: Color(red: 0.39, green: 0.26, blue: 0.02),
                                   gradientStart: Color(red: 1.00, green: 0.90, blue: 0.58),
                                   gradientEnd: Color(red: 0.95, green: 0.73, blue: 0.24),
                                   glow: Color(red: 1.00, green: 0.78, blue: 0.28))
        static let coral = Palette(icon: Color(red: 0.43, green: 0.07, blue: 0.11),
                                   gradientStart: Color(red: 1.00, green: 0.78, blue: 0.76),
                                   gradientEnd: Color(red: 0.95, green: 0.44, blue: 0.44),
                                   glow: Color(red: 0.98, green: 0.46, blue: 0.46))
        static let emerald = Palette(icon: Color(red: 0.05, green: 0.35, blue: 0.15),
                                     gradientStart: Color(red: 0.73, green: 0.95, blue: 0.77),
                                     gradientEnd: Color(red: 0.34, green: 0.80, blue: 0.47),
                                     glow: Color(red: 0.29, green: 0.83, blue: 0.49))
        static let cyan = Palette(icon: Color(red: 0.05, green: 0.29, blue: 0.45),
                                  gradientStart: Color(red: 0.74, green: 0.93, blue: 1.00),
                                  gradientEnd: Color(red: 0.40, green: 0.73, blue: 0.95),
                                  glow: Color(red: 0.37, green: 0.78, blue: 0.98))
        static let indigo = Palette(icon: Color(red: 0.06, green: 0.18, blue: 0.39),
                                    gradientStart: Color(red: 0.74, green: 0.84, blue: 1.00),
                                    gradientEnd: Color(red: 0.44, green: 0.58, blue: 0.95),
                                    glow: Color(red: 0.46, green: 0.66, blue: 1.00))
        static let violet = Palette(icon: Color(red: 0.20, green: 0.11, blue: 0.45),
                                    gradientStart: Color(red: 0.88, green: 0.83, blue: 1.00),
                                    gradientEnd: Color(red: 0.64, green: 0.55, blue: 0.95),
                                    glow: Color(red: 0.65, green: 0.53, blue: 0.96))
        static let slate = Palette(icon: Color(red: 0.17, green: 0.22, blue: 0.32),
                                   gradientStart: Color(red: 0.90, green: 0.93, blue: 0.98),
                                   gradientEnd: Color(red: 0.66, green: 0.74, blue: 0.86),
                                   glow: Color(red: 0.56, green: 0.66, blue: 0.82))
    }

    let icon: KeyPath<CompoundIcons, Image>
    let palette: Palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [
                    palette.gradientStart,
                    palette.gradientEnd
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(LinearGradient(colors: [
                            Color.white.opacity(0.65),
                            Color.white.opacity(0.18)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9)
                }
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(LinearGradient(colors: [
                            Color.white.opacity(0.42),
                            Color.white.opacity(0.02)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 13, height: 13)
                        .offset(x: 5, y: 4)
                }
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [
                            Color.white.opacity(0.36),
                            Color.clear
                        ], startPoint: .top, endPoint: .bottom))
                        .frame(height: 8)
                        .padding(.horizontal, 5)
                        .offset(y: 1)
                }
                .shadow(color: palette.glow.opacity(0.32), radius: 9, x: 0, y: 4)

            CompoundIcon(icon, size: .medium, relativeTo: .compound.bodyLG)
                .foregroundColor(palette.icon)
                .shadow(color: Color.white.opacity(0.25), radius: 0, x: 0, y: 1)
        }
        .frame(width: 40, height: 40)
    }
}

struct SettingsScreen: View {
    let context: SettingsScreenViewModel.Context
    
    var body: some View {
        Form {
            userSection
            
            accountAndSecuritySection
            
            generalSection
            
            signOutSection
        }
        .compoundList()
        .scrollContentBackground(.hidden)
        .salemScreenBackground()
        .navigationTitle(L10n.commonSettings)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
    }
    
    private var userSection: some View {
        Section {
            ListRow(kind: .custom {
                Button {
                    context.send(viewAction: .userDetails)
                } label: {
                    HStack(spacing: 12) {
                        LoadableAvatarImage(url: context.viewState.userAvatarURL,
                                            name: context.viewState.userDisplayName,
                                            contentID: context.viewState.userID,
                                            avatarSize: .user(on: .settings),
                                            mediaProvider: context.mediaProvider)
                            .accessibilityHidden(true)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.viewState.userDisplayName ?? "")
                                .font(.compound.headingMD)
                                .foregroundColor(.compound.textPrimary)
                            Text(context.viewState.userID)
                                .font(.compound.bodySM)
                                .foregroundColor(.compound.textSecondary)
                        }
                        
                        Spacer()
                        
                        ListRowAccessory.navigationLink
                    }
                    .padding(.horizontal, ListRowPadding.horizontal)
                    .padding(.vertical, 8)
                }
            })
        }
    }
    
    private var accountAndSecuritySection: some View {
        Section(L10n.screenSettingsAccountAndSecurityTitle) {
            ListRow(label: .default(title: L10n.screenNotificationSettingsTitle,
                                    icon: SettingsTintedIcon(icon: \.notifications,
                                                             palette: .amber)),
                    kind: .navigationLink {
                        context.send(viewAction: .notifications)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.notifications)
            
            ListRow(label: .default(title: L10n.commonScreenLock,
                                    icon: SettingsTintedIcon(icon: \.lock,
                                                             palette: .coral)),
                    kind: .navigationLink {
                        context.send(viewAction: .appLock)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.screenLock)
            
            switch context.viewState.securitySectionMode {
            case .secureBackup:
                ListRow(label: .default(title: L10n.commonEncryption,
                                        icon: SettingsTintedIcon(icon: \.key,
                                                                 palette: .emerald)),
                        details: context.viewState.showSecuritySectionBadge ? .icon(securitySectionBadge) : nil,
                        kind: .navigationLink { context.send(viewAction: .secureBackup) })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.secureBackup)
            default:
                EmptyView()
            }
            
            if context.viewState.showLinkNewDeviceButton {
                ListRow(label: .default(title: L10n.commonLinkNewDevice,
                                        icon: SettingsTintedIcon(icon: \.devices,
                                                                 palette: .cyan)),
                        kind: .navigationLink {
                            context.send(viewAction: .linkNewDevice)
                        })
            }
            
            if let url = context.viewState.accountProfileURL {
                ListRow(label: .default(title: L10n.actionManageAccount,
                                        icon: SettingsTintedIcon(icon: \.userProfile,
                                                                 palette: .indigo)),
                        kind: .button {
                            context.send(viewAction: .manageAccount(url: url))
                        })
                        .accessibilityIdentifier(A11yIdentifiers.settingsScreen.account)
            }
            
            if let url = context.viewState.accountSessionsListURL {
                ListRow(label: .default(title: L10n.actionManageDevices,
                                        icon: SettingsTintedIcon(icon: \.devices,
                                                                 palette: .violet)),
                        kind: .button {
                            context.send(viewAction: .manageAccount(url: url))
                        })
            }
            
            if context.viewState.showBlockedUsers {
                ListRow(label: .default(title: L10n.commonBlockedUsers,
                                        icon: SettingsTintedIcon(icon: \.block,
                                                                 palette: .coral)),
                        kind: .navigationLink {
                            context.send(viewAction: .blockedUsers)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.settingsScreen.blockedUsers)
            }
        }
    }
    
    private var generalSection: some View {
        Section {
            ListRow(label: .default(title: L10n.commonAdvancedSettings,
                                    icon: SettingsTintedIcon(icon: \.settings,
                                                             palette: .amber)),
                    kind: .navigationLink {
                        context.send(viewAction: .advancedSettings)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.advancedSettings)

            #if DEBUG
            ListRow(label: .default(title: L10n.commonDeveloperOptions,
                                    icon: SettingsTintedIcon(icon: \.settings,
                                                             palette: .cyan)),
                    kind: .navigationLink {
                        context.send(viewAction: .developerOptions)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.developerOptions)
            #endif

            ListRow(label: .default(title: L10n.screenAboutSalemxTitle,
                                    icon: SettingsTintedIcon(icon: \.info,
                                                             palette: .slate)),
                    kind: .navigationLink {
                        context.send(viewAction: .about)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.about)
        }
    }
    
    private var signOutSection: some View {
        Section {
            ListRow(label: .action(title: L10n.screenSignoutPreferenceItem,
                                   icon: \.signOut,
                                   role: .destructive),
                    kind: .button {
                        context.send(viewAction: .logout)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.logout)
            
            if context.viewState.showAccountDeactivation {
                ListRow(label: .action(title: L10n.actionDeactivateAccount,
                                       icon: \.warning,
                                       role: .destructive),
                        kind: .navigationLink {
                            context.send(viewAction: .deactivateAccount)
                        })
            }
        }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.actionDone) { context.send(viewAction: .close) }
                .accessibilityIdentifier(A11yIdentifiers.settingsScreen.done)
        }
    }
    
    @ViewBuilder
    private var securitySectionBadge: some View {
        if context.viewState.showSecuritySectionBadge {
            BadgeView(size: 10)
        }
    }
}

// MARK: - Previews

struct SettingsScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    static let bugReportDisabledViewModel = makeViewModel(isBugReportServiceEnabled: false)
    
    static var previews: some View {
        ElementNavigationStack {
            SettingsScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.accountSessionsListURL).map { $0 != nil })
        .previewDisplayName("Default")
        
        ElementNavigationStack {
            SettingsScreen(context: bugReportDisabledViewModel.context)
        }
        .snapshotPreferences(expect: bugReportDisabledViewModel.context.observe(\.viewState.accountSessionsListURL).map { $0 != nil })
        .previewDisplayName("Bug report disabled")
    }
    
    static func makeViewModel(isBugReportServiceEnabled: Bool = true) -> SettingsScreenViewModel {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@userid:example.com",
                                                                                   deviceID: "AAAAAAAAAAA"))))
        return SettingsScreenViewModel(userSession: userSession,
                                       appSettings: ServiceLocator.shared.settings,
                                       isBugReportServiceEnabled: isBugReportServiceEnabled)
    }
}
