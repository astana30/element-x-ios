//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Testing
@testable import ElementX

struct ProductionDispatchActivationBuildTests {
    @Test
    func productionDispatchDefaultMatchesTheBoundedBuildConfiguration() {
        #expect(AppSettings.salemxProductionDispatchV1DefaultEnabled == AppSettings.salemxProductionDispatchV1ActivationBuild)
    }

    @Test
    func activationOverrideForcesTheFeatureFlagOnlyOnActivationBuilds() {
        let appSettings = AppSettings()
        let previousValue = appSettings.salemxProductionDispatchV1Enabled
        defer { appSettings.salemxProductionDispatchV1Enabled = previousValue }

        appSettings.salemxProductionDispatchV1Enabled = false
        AppSettings.applyProductionDispatchActivationOverride(to: appSettings)
        #expect(appSettings.salemxProductionDispatchV1Enabled == AppSettings.salemxProductionDispatchV1ActivationBuild)
    }
}
