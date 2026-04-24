//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

struct InfoPlistReader {
    private enum Keys {
        static let appGroupIdentifier = "appGroupIdentifier"
        static let baseBundleIdentifier = "baseBundleIdentifier"
        static let keychainAccessGroupIdentifier = "keychainAccessGroupIdentifier"
        static let pushGatewayBaseURL = "pushGatewayBaseURL"
        static let bundleShortVersion = "CFBundleShortVersionString"
        static let bundleDisplayName = "CFBundleDisplayName"
        static let productionAppName = "productionAppName"
        static let utExportedTypeDeclarationsKey = "UTExportedTypeDeclarations"
        static let utTypeIdentifierKey = "UTTypeIdentifier"
        static let utDescriptionKey = "UTTypeDescription"
        
        static let bundleURLTypes = "CFBundleURLTypes"
        static let bundleURLName = "CFBundleURLName"
        static let bundleURLSchemes = "CFBundleURLSchemes"
    }
    
    private enum Values {
        static let defaultPushGatewayBaseURL = "https://matrix.org"
        static let mentionPills = "Mention Pills"
    }

    /// Info.plist reader on the bundle object that contains the current executable.
    static let main = InfoPlistReader(bundle: .main)

    /// Info.plist reader on the bundle object that contains the main app executable.
    static let app = InfoPlistReader(bundle: .app)

    private let bundle: Bundle

    /// Initializer
    /// - Parameter bundle: bundle to read values from
    init(bundle: Bundle) {
        self.bundle = bundle
    }

    /// App group identifier set in Info.plist of the target
    var appGroupIdentifier: String {
        infoPlistValue(forKey: Keys.appGroupIdentifier)
    }

    /// Base bundle identifier set in Info.plist of the target
    var baseBundleIdentifier: String {
        infoPlistValue(forKey: Keys.baseBundleIdentifier)
    }
    
    /// Keychain access group identifier set in Info.plist of the target
    var keychainAccessGroupIdentifier: String {
        infoPlistValue(forKey: Keys.keychainAccessGroupIdentifier)
    }
    
    /// Push gateway base URL set in Info.plist of the target
    var pushGatewayBaseURL: URL {
        let stringValue: String = infoPlistValue(forKey: Keys.pushGatewayBaseURL)
        let resolvedValue: String
        if stringValue.hasPrefix("$(") {
            NSLog("[InfoPlistReader] Unresolved \(Keys.pushGatewayBaseURL) build setting. Falling back to \(Values.defaultPushGatewayBaseURL).")
            resolvedValue = Values.defaultPushGatewayBaseURL
        } else {
            resolvedValue = stringValue
        }
        
        if let url = URL(string: resolvedValue) {
            return url
        }
        
        assertionFailure("Invalid \(Keys.pushGatewayBaseURL), falling back to \(Values.defaultPushGatewayBaseURL)")
        guard let fallbackURL = URL(string: Values.defaultPushGatewayBaseURL) else {
            fatalError("Invalid default \(Keys.pushGatewayBaseURL)")
        }
        return fallbackURL
    }

    /// Bundle executable of the target
    var bundleExecutable: String {
        infoPlistValue(forKey: kCFBundleExecutableKey as String)
    }

    /// Bundle identifier of the target
    var bundleIdentifier: String {
        infoPlistValue(forKey: kCFBundleIdentifierKey as String)
    }

    /// Bundle short version string of the target
    var bundleShortVersionString: String {
        infoPlistValue(forKey: Keys.bundleShortVersion)
    }

    /// Bundle version of the target
    var bundleVersion: String {
        infoPlistValue(forKey: kCFBundleVersionKey as String)
    }

    /// Bundle display name of the target
    var bundleDisplayName: String {
        infoPlistValue(forKey: Keys.bundleDisplayName)
    }
    
    /// The name of the non-X app when it becomes production ready.
    var productionAppName: String {
        infoPlistValue(forKey: Keys.productionAppName)
    }
    
    // MARK: - Custom App Scheme
    
    var appScheme: String {
        customSchemeForName("Application")
    }
    
    var elementCallScheme: String {
        customSchemeForName("Element Call")
    }
    
    // MARK: - Mention Pills

    /// Mention Pills UTType
    var pillsUTType: String {
        let exportedTypes: [[String: Any]] = infoPlistValue(forKey: Keys.utExportedTypeDeclarationsKey)
        guard let mentionPills = exportedTypes.first(where: { $0[Keys.utDescriptionKey] as? String == Values.mentionPills }),
              let utType = mentionPills[Keys.utTypeIdentifierKey] as? String else {
            fatalError("Add properly \(Values.mentionPills) exported type into your target's Info.plist")
        }
        
        // The pills type is formed from the baseBundleIdentifier, however weirdly, if a fork sets that with a value
        // that includes one or more uppercase characters, pill rendering breaks. If we lowercase the type identifier
        // the bug is fixed, even though the value used in the fork's Info.plist no longer matches the value returned.
        // Maybe in the future the fork should set their own PILLS_UT_TYPE_IDENTIFIER, but for now this works 🤷‍♂️🤷‍♂️🤷‍♂️
        return utType.lowercased()
    }
    
    // MARK: - Private
    
    private func infoPlistValue<T>(forKey key: String) -> T {
        guard let result = bundle.object(forInfoDictionaryKey: key) as? T else {
            fatalError("Add \(key) into your target's Info.plst")
        }
        return result
    }
    
    private func customSchemeForName(_ name: String) -> String {
        let urlTypes: [[String: Any]] = infoPlistValue(forKey: Keys.bundleURLTypes)
        
        if let urlType = urlTypes.first(where: { $0[Keys.bundleURLName] as? String == name }),
           let urlSchemes = urlType[Keys.bundleURLSchemes] as? [String],
           let scheme = urlSchemes.first,
           !scheme.isEmpty {
            return scheme
        }
        
        let fallbackScheme = urlTypes
            .compactMap { $0[Keys.bundleURLSchemes] as? [String] }
            .flatMap { $0 }
            .first { !$0.isEmpty && $0 != "matrix" && $0 != "io.element.call" }
        
        if let fallbackScheme {
            assertionFailure("Missing URL type named \(name). Falling back to \(fallbackScheme)")
            return fallbackScheme
        }
        
        let bundleID = bundle.bundleIdentifier ?? "app"
        assertionFailure("Invalid custom application scheme configuration, falling back to bundle identifier")
        return bundleID.lowercased()
    }
}
