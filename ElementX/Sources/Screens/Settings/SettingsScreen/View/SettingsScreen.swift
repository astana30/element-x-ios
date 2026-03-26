//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SFSafeSymbols
import SwiftUI

private struct SettingsTintedIcon: View {
    let icon: KeyPath<CompoundIcons, Image>
    let foreground: Color
    let background: Color

    var body: some View {
        CompoundIcon(icon, size: .medium, relativeTo: .compound.bodyLG)
            .foregroundColor(foreground)
            .frame(width: 36, height: 36)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(stops: [
                            .init(color: background.opacity(0.98), location: 0.00),
                            .init(color: background.opacity(0.90), location: 0.62),
                            .init(color: background.opacity(0.82), location: 1.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.42), lineWidth: 0.8)
                            .blendMode(.plusLighter)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(stops: [
                                    .init(color: Color.white.opacity(0.24), location: 0.00),
                                    .init(color: Color.white.opacity(0.10), location: 0.30),
                                    .init(color: Color.clear, location: 0.62)
                                ],
                                startPoint: .top,
                                endPoint: .bottom))
                    }
                    .shadow(color: foreground.opacity(0.10), radius: 8, x: 0, y: 4)
            }
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
                                                             foreground: Color(red: 0.77, green: 0.58, blue: 0.06),
                                                             background: Color(red: 1.00, green: 0.94, blue: 0.79))),
                    kind: .navigationLink {
                        context.send(viewAction: .notifications)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.notifications)
            
            ListRow(label: .default(title: L10n.commonScreenLock,
                                    icon: SettingsTintedIcon(icon: \.lock,
                                                             foreground: Color(red: 0.76, green: 0.28, blue: 0.24),
                                                             background: Color(red: 1.00, green: 0.90, blue: 0.88))),
                    kind: .navigationLink {
                        context.send(viewAction: .appLock)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.screenLock)
            
            switch context.viewState.securitySectionMode {
            case .secureBackup:
                ListRow(label: .default(title: L10n.commonEncryption,
                                        icon: SettingsTintedIcon(icon: \.key,
                                                                 foreground: Color(red: 0.19, green: 0.57, blue: 0.28),
                                                                 background: Color(red: 0.88, green: 0.97, blue: 0.89))),
                        details: context.viewState.showSecuritySectionBadge ? .icon(securitySectionBadge) : nil,
                        kind: .navigationLink { context.send(viewAction: .secureBackup) })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.secureBackup)
            default:
                EmptyView()
            }
            
            if context.viewState.showLinkNewDeviceButton {
                ListRow(label: .default(title: L10n.commonLinkNewDevice,
                                        icon: \.devices),
                        kind: .navigationLink {
                            context.send(viewAction: .linkNewDevice)
                        })
            }
            
            if let url = context.viewState.accountProfileURL {
                ListRow(label: .default(title: L10n.actionManageAccount,
                                        icon: SettingsTintedIcon(icon: \.userProfile,
                                                                 foreground: Color(red: 0.13, green: 0.43, blue: 0.82),
                                                                 background: Color(red: 0.88, green: 0.94, blue: 1.00))),
                        kind: .button {
                            context.send(viewAction: .manageAccount(url: url))
                        })
                        .accessibilityIdentifier(A11yIdentifiers.settingsScreen.account)
            }
            
            if let url = context.viewState.accountSessionsListURL {
                ListRow(label: .default(title: L10n.actionManageDevices,
                                        icon: SettingsTintedIcon(icon: \.devices,
                                                                 foreground: Color(red: 0.13, green: 0.43, blue: 0.82),
                                                                 background: Color(red: 0.88, green: 0.94, blue: 1.00))),
                        kind: .button {
                            context.send(viewAction: .manageAccount(url: url))
                        })
            }
            
            if context.viewState.showBlockedUsers {
                ListRow(label: .default(title: L10n.commonBlockedUsers,
                                        icon: \.block),
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
                                                             foreground: Color(red: 0.53, green: 0.38, blue: 0.20),
                                                             background: Color(red: 0.95, green: 0.90, blue: 0.84))),
                    kind: .navigationLink {
                        context.send(viewAction: .advancedSettings)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.settingsScreen.advancedSettings)

            ListRow(label: .default(title: L10n.screenAboutSalemxTitle,
                                    icon: SettingsTintedIcon(icon: \.info,
                                                             foreground: Color(red: 0.34, green: 0.42, blue: 0.54),
                                                             background: Color(red: 0.92, green: 0.94, blue: 0.97))),
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
