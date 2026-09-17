import ProjectDescription
import ProjectDescriptionHelpers
import CoreSpotlight

let sharedEntitlements: [String: Plist.Value] = [
    "com.apple.security.application-groups": ["group.com.jibunkit.shared"],
]
let appBuild = try EnabledFeatureBuildRequirements.app.compose(infoPlist: [
    "CFBundleDisplayName": "JibunKit", "CFBundleShortVersionString": "0.8.3",
    "CFBundleVersion": "13", "JibunKitAppGroup": "group.com.jibunkit.shared",
    "CFBundleAllowMixedLocalizations": true,
    "LSSupportsOpeningDocumentsInPlace": true,
    "CFBundleDocumentTypes": [[
        "CFBundleTypeName": "JibunKit Incoming File",
        "CFBundleTypeRole": "Viewer", "LSHandlerRank": "Alternate",
        "LSItemContentTypes": ["public.data"],
    ]],
    "UILaunchScreen": [:],
    "NSUserActivityTypes": [.string(CSSearchableItemActionType)],
    "CFBundleURLTypes": [[
        "CFBundleURLName": "com.jibunkit.app.mini-app",
        "CFBundleURLSchemes": ["jibunkit"],
    ]],
], entitlements: sharedEntitlements, localizedInfoPlist: [
    "en": ["CFBundleDisplayName": "JibunKit"],
    "ja": ["CFBundleDisplayName": "JibunKit"],
])
let widgetBuild = try EnabledFeatureBuildRequirements.widget.compose(infoPlist: [
    "CFBundleShortVersionString": "0.8.3", "CFBundleVersion": "13",
    "JibunKitAppGroup": "group.com.jibunkit.shared",
    "CFBundleAllowMixedLocalizations": true,
    "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"],
], entitlements: sharedEntitlements, localizedInfoPlist: [
    "en": ["CFBundleDisplayName": "JibunKit Widget"],
    "ja": ["CFBundleDisplayName": "JibunKitウィジェット"],
])

try FeatureAppShortcuts.writeProvider([
    FeatureAppShortcuts(owner: "counter", imports: [],
        sourceFile: "Sources/CounterIntegration/AppShortcuts.swift.fragment"),
], to: "GeneratedFeatureSources/JibunKitShortcuts.swift")

let generatedFeatureResources = "GeneratedFeatureResources"
try appBuild.writeLocalizedInfoPlistStrings(to: "\(generatedFeatureResources)/App")
try widgetBuild.writeLocalizedInfoPlistStrings(to: "\(generatedFeatureResources)/Widget")

let project = Project(
    name: "JibunKit",
    packages: [.package(path: "."), .package(path: "Modules/Zaiko")],
    settings: .settings(base: ["SWIFT_VERSION": "6.0"]),
    targets: [
        .target(
            name: "BackupHarness", destinations: .iOS, product: .app,
            bundleId: "com.jibunkit.backup-harness", deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
            sources: ["Tests/BackupHarness/**", "Sources/JibunKit/BackupScreen.swift", "Sources/JibunKit/BackupDocument.swift"],
            dependencies: [.package(product: "JibunKitCore"), .package(product: "JibunKitBackup"), .package(product: "CounterFeature"), .package(product: "ReminderFeature")]
        ),
        .target(
            name: "JibunKit-App", destinations: .iOS, product: .app,
            bundleId: "com.jibunkit.app", deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: appBuild.infoPlist),
            sources: ["Sources/JibunKit/**", "GeneratedFeatureSources/**"],
            resources: ["GeneratedFeatureResources/App/**"],
            entitlements: .dictionary(appBuild.entitlements),
            dependencies: [.package(product: "JibunKitCore"), .package(product: "JibunKitBackup"), .package(product: "CounterFeature"),
                           .package(product: "ReminderFeature"), .package(product: "CounterIntegration"),
                           .package(product: "ReminderIntegration"), .package(product: "ZaikoIntegration"),
                           .target(name: "JibunKitWidget-Extension"),
                           .target(name: "JibunKitShare-Extension")]
        ),
        .target(
            name: "JibunKitWidget-Extension", destinations: .iOS, product: .appExtension,
            bundleId: "com.jibunkit.app.Widget", deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: widgetBuild.infoPlist),
            sources: ["Sources/JibunKitWidget/**"],
            resources: ["GeneratedFeatureResources/Widget/**"],
            entitlements: .dictionary(widgetBuild.entitlements),
            dependencies: [.package(product: "CounterFeature"), .package(product: "JibunKitCore")]
        ),
        .target(
            name: "JibunKitShare-Extension", destinations: .iOS, product: .appExtension,
            bundleId: "com.jibunkit.app.Share", deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "JibunKit", "CFBundleShortVersionString": "0.8.3", "CFBundleVersion": "13",
                "JibunKitAppGroup": "group.com.jibunkit.shared",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.share-services",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ShareViewController",
                    "NSExtensionAttributes": [
                        "NSExtensionActivationRule": "extensionItems.@count > 0 AND SUBQUERY(extensionItems, $item, $item.attachments.@count > 0 AND SUBQUERY($item.attachments, $attachment, ANY $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO 'public.data').@count == $item.attachments.@count).@count == extensionItems.@count",
                    ],
                ],
            ]),
            sources: ["Sources/JibunKitShare/**"],
            entitlements: .dictionary(sharedEntitlements),
            dependencies: [.package(product: "JibunKitCore")],
            settings: .settings(base: ["APPLICATION_EXTENSION_API_ONLY": "YES"])
        ),
        .target(
            name: "MigrationUITests", destinations: .iOS, product: .uiTests,
            bundleId: "com.jibunkit.migration-tests", deploymentTargets: .iOS("26.0"),
            infoPlist: .default, sources: ["UITests/**"],
            dependencies: [.target(name: "JibunKit-App")]
        ),
        .target(
            name: "IncomingNativeTests", destinations: .iOS, product: .unitTests,
            bundleId: "com.jibunkit.incoming-tests", deploymentTargets: .iOS("26.0"),
            infoPlist: .default,
            sources: ["Tests/JibunKitCoreTests/MiniAppIncoming*.swift"],
            dependencies: [.target(name: "JibunKit-App"), .package(product: "JibunKitCore")]
        ),
        .target(
            name: "CounterExample", destinations: .iOS, product: .app,
            bundleId: "com.jibunkit.counterexample", deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
            sources: ["Examples/Counter/**"],
            dependencies: [.package(product: "CounterFeature"), .package(product: "JibunKitCore")]
        ),
    ],
    schemes: [
        .scheme(name: "IncomingNativeTests", shared: true,
                buildAction: .buildAction(targets: ["JibunKit-App"]),
                testAction: .targets(["IncomingNativeTests"], configuration: .debug)),
        .scheme(name: "MigrationUITests", shared: true,
                buildAction: .buildAction(targets: ["JibunKit-App"]),
                testAction: .targets(["MigrationUITests"], configuration: .debug)),
    ]
)
