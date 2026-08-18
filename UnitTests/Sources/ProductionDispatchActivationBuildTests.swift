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
}
