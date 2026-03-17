//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct LegalInformationScreen: View {
    let context: LegalInformationScreenViewModel.Context
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("SalemX")
                        .font(.compound.headingLG)
                        .foregroundColor(.compound.textPrimary)
                    
                    Text(L10n.screenAboutSalemxDescriptionPrimary)
                        .font(.compound.bodyMD)
                        .foregroundColor(.compound.textPrimary)
                    
                    Text(L10n.screenAboutSalemxDescriptionSecondary)
                        .font(.compound.bodyMD)
                        .foregroundColor(.compound.textSecondary)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.compound.bgCanvasDefault)
            }
            
            Section(L10n.screenAboutSalemxDocumentsTitle) {
                ListRow(label: .plain(title: L10n.commonCopyright),
                        kind: .button { openURL(context.viewState.copyrightURL) })
                
                ListRow(label: .plain(title: L10n.commonAcceptableUsePolicy),
                        kind: .button { openURL(context.viewState.acceptableUseURL) })
                
                ListRow(label: .plain(title: L10n.commonPrivacyPolicy),
                        kind: .button { openURL(context.viewState.privacyURL) })
            }
        }
        .compoundList()
        .navigationTitle(L10n.screenAboutSalemxTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

struct LegalInformationScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = LegalInformationScreenViewModel(appSettings: AppSettings())
    
    static var previews: some View {
        LegalInformationScreen(context: viewModel.context)
    }
}
