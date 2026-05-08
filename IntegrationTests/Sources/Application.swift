//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import XCTest

enum Application {
    @discardableResult static func launch() -> XCUIApplication {
        let app = XCUIApplication()
        
        var launchEnvironment = [
            "IS_RUNNING_INTEGRATION_TESTS": "1"
        ]
        let diagnosticEnvironmentKeys = [
            "NATIVE_DIRECT_CALL_DIAGNOSTICS",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED",
            "UI_TESTS_SIGNALLING_CHANNEL"
        ]
        for key in diagnosticEnvironmentKeys {
            if let value = ProcessInfo.processInfo.environment[key], value.isEmpty == false {
                launchEnvironment[key] = value
            }
        }
        
        app.launchEnvironment = launchEnvironment
        app.launch()
        
        return app
    }
}

extension XCUIApplication {
    var homeserver: String? {
        guard let homeserver = ProcessInfo.processInfo.environment["INTEGRATION_TESTS_HOST"],
              homeserver.count > 0 else {
            return nil
        }
        
        return homeserver
    }
    
    var username: String {
        guard let username = ProcessInfo.processInfo.environment["INTEGRATION_TESTS_USERNAME"],
              username.count > 0 else {
            return "default"
        }
        
        return username
    }
    
    var password: String {
        guard let password = ProcessInfo.processInfo.environment["INTEGRATION_TESTS_PASSWORD"],
              password.count > 0 else {
            return "default"
        }
        
        return password
    }
}
