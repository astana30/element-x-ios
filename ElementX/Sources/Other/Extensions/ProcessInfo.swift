//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

extension ProcessInfo {
    /// Flag indicating whether the app is running the unit tests.
    static var isRunningUnitTests: Bool {
        #if DEBUG
        processInfo.environment["IS_RUNNING_UNIT_TESTS"] == "1"
        #else
        false
        #endif
    }

    /// Flag indicating whether the app is running the UI tests.
    static var isRunningUITests: Bool {
        #if DEBUG
        processInfo.environment["UI_TESTS_SCREEN"] != nil
        #else
        false
        #endif
    }
    
    static var isRunningIntegrationTests: Bool {
        #if DEBUG
        processInfo.environment["IS_RUNNING_INTEGRATION_TESTS"] == "1"
        #else
        false
        #endif
    }
    
    static var isRunningAccessibilityTests: Bool {
        #if DEBUG
        processInfo.environment["ACCESSIBILITY_VIEW"] != nil
        #else
        false
        #endif
    }

    /// Flag indicating whether the app is running the UI tests or unit tests.
    static var isRunningTests: Bool {
        isRunningUITests || isRunningUnitTests || isRunningIntegrationTests || isRunningAccessibilityTests
    }
    
    /// The identifier of the screen to be loaded when running UI tests.
    static var testScreenID: UITestsScreenIdentifier? {
        #if DEBUG
        processInfo.environment["UI_TESTS_SCREEN"].flatMap(UITestsScreenIdentifier.init)
        #else
        nil
        #endif
    }
    
    /// The identifier of the preview that will be accessibility tested
    static var accessibilityViewID: String? {
        #if DEBUG
        processInfo.environment["ACCESSIBILITY_VIEW"]
        #else
        nil
        #endif
    }
    
    static var shouldDisableTimelineAccessibility: Bool {
        guard isRunningUITests else {
            return false
        }
        
        #if DEBUG
        return processInfo.environment["UI_TESTS_DISABLE_TIMELINE_ACCESSIBILITY"] != nil
        #else
        return false
        #endif
    }
    
    static var isNativeDirectCallDiagnosticUITestHarnessEnabled: Bool {
        #if DEBUG
        isRunningUITests && processInfo.environment["UI_TESTS_NATIVE_DIRECT_CALL_DIAGNOSTICS"] == "1"
        #else
        false
        #endif
    }

    static var isNativeDirectCallDiagnosticUITestCommandsEnabled: Bool {
        #if DEBUG
        isNativeDirectCallDiagnosticUITestHarnessEnabled && processInfo.environment["UI_TESTS_NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED"] == "1"
        #else
        false
        #endif
    }

    static var isNativeDirectCallDiagnosticIntegrationHarnessEnabled: Bool {
        #if DEBUG
        isNativeDirectCallDiagnosticIntegrationHarnessEnabled(environment: processInfo.environment)
        #else
        false
        #endif
    }

    static var isNativeDirectCallDiagnosticIntegrationCommandsEnabled: Bool {
        #if DEBUG
        isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: processInfo.environment)
        #else
        false
        #endif
    }

    static var isNativeDirectCallDiagnosticIntegrationEncryptionEnabled: Bool {
        #if DEBUG
        isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: processInfo.environment)
        #else
        false
        #endif
    }

    static var isNativeDirectCallDiagnosticIntegrationLiveKitEnabled: Bool {
        #if DEBUG
        isNativeDirectCallDiagnosticIntegrationLiveKitEnabled(environment: processInfo.environment)
        #else
        false
        #endif
    }

    static var isNativeDirectCallPrivateDogfoodEnabled: Bool {
        #if DEBUG
        isNativeDirectCallPrivateDogfoodEnabled(environment: processInfo.environment)
        #else
        false
        #endif
    }

    static var isNativeDirectCallProductionStartEnabled: Bool {
        #if DEBUG
        isNativeDirectCallProductionStartEnabled(environment: processInfo.environment)
        #else
        false
        #endif
    }

    static var isNativeDirectCallInternalUIEnabled: Bool {
        #if DEBUG
        isNativeDirectCallInternalUIEnabled(environment: processInfo.environment)
        #else
        false
        #endif
    }

    static var isNativeDirectCallProductUIEnabled: Bool {
        #if DEBUG
        isNativeDirectCallProductUIEnabled(environment: processInfo.environment)
        #else
        false
        #endif
    }

    static var isNativeDirectCallEligibilityStatusEnabled: Bool {
        #if DEBUG
        isNativeDirectCallEligibilityStatusEnabled(environment: processInfo.environment)
        #else
        false
        #endif
    }

    static var isNativeDirectCallInternalPilotRolloutEnabled: Bool {
        #if DEBUG
        isNativeDirectCallInternalPilotRolloutEnabled(environment: processInfo.environment)
        #else
        false
        #endif
    }

    static var isXcodePreview: Bool {
        #if DEBUG
        processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        #else
        false
        #endif
    }
}

#if DEBUG
extension ProcessInfo {
    static func isNativeDirectCallDiagnosticIntegrationHarnessEnabled(environment: [String: String]) -> Bool {
        environment["IS_RUNNING_INTEGRATION_TESTS"] == "1" && environment["NATIVE_DIRECT_CALL_DIAGNOSTICS"] == "1"
    }

    static func isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: [String: String]) -> Bool {
        isNativeDirectCallDiagnosticIntegrationHarnessEnabled(environment: environment) && environment["NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED"] == "1"
    }

    static func isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: [String: String]) -> Bool {
        let encryptionGateEnvironmentKey = "NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION"
        let secretEnvironmentKey = "NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION_SECRET"

        return isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: environment) &&
            environment[encryptionGateEnvironmentKey] == "1" &&
            environment[secretEnvironmentKey]?.isEmpty == false
    }

    static func isNativeDirectCallDiagnosticIntegrationLiveKitEnabled(environment: [String: String]) -> Bool {
        isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: environment) &&
            environment["NATIVE_DIRECT_CALL_DIAGNOSTIC_LIVEKIT"] == "1"
    }

    static func isNativeDirectCallPrivateDogfoodEnabled(environment: [String: String]) -> Bool {
        isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: environment) &&
            environment["NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED"] == "1"
    }

    static func isNativeDirectCallProductionStartEnabled(environment: [String: String]) -> Bool {
        isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: environment) &&
            environment["NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED"] == "1"
    }

    static func isNativeDirectCallInternalUIEnabled(environment: [String: String]) -> Bool {
        isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: environment) &&
            environment["NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED"] == "1"
    }

    static func isNativeDirectCallProductUIEnabled(environment: [String: String]) -> Bool {
        isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: environment) &&
            environment["NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED"] == "1"
    }

    static func isNativeDirectCallEligibilityStatusEnabled(environment: [String: String]) -> Bool {
        isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: environment) &&
            environment["NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED"] == "1"
    }

    static func isNativeDirectCallInternalPilotRolloutEnabled(environment: [String: String]) -> Bool {
        isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: environment) &&
            environment["NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED"] == "1"
    }

    static func nativeDirectCallProductionTokenBaseURL(environment: [String: String]) -> URL? {
        guard isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: environment),
              let value = environment["NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL"],
              !value.isEmpty else {
            return nil
        }

        return URL(string: value)
    }
}
#endif
