"""Connect all adopted P2 diagnostics to one disposable normal host.

This prepares source only. It does not claim a native build or device result.
Every input, destination, and single-use host anchor is validated before writes.
"""
import argparse
from pathlib import Path


DIAGNOSTIC_FAMILIES = (
    "P2Background", "P2Location", "P2Identity", "P2Push",
    "P2Bluetooth", "P2Scenes", "P2AR", "P2Action",
    "P2Appearance", "P2WidgetLocalization", "P1Incoming",
)

APP_EXPECTED_SOURCES = (
    "Tests/P2Background/P2BackgroundObservationLog.swift",
    "Tests/P2Background/P2BackgroundTransferEvidence.swift",
    "Tests/P2Background/P2BackgroundProbe.swift",
    "Tests/P2Background/P2ContinuedNativeComparison.swift",
    "Tests/P2Location/P2LocationObservationLog.swift",
    "Tests/P2Location/P2LocationProbe.swift",
    "Tests/P2Identity/P2IdentityProbe.swift",
    "Tests/P2Push/P2PushProbe.swift",
    "Tests/P2Bluetooth/P2BluetoothProbe.swift",
    "Tests/P2Scenes/P2ScenesProbe.swift",
    "Tests/P2AR/P2ARProbe.swift",
    "Tests/P2Appearance/P2AppearanceProbe.swift",
    "Tests/TemplateIntegration/P1IncomingProbe.swift",
)

NATIVE_EXPECTED_SOURCES = (
    "Tests/P2Background/P2BackgroundNativeTests.swift",
    "Tests/P2Location/P2LocationNativeTests.swift",
    "Tests/P2CombinedHost/HostNativeTests.swift",
    "Tests/P2IdentityPushHost/HostNativeTests.swift",
    "Tests/P2Identity/P2IdentityNativeTests.swift",
    "Tests/P2Push/P2PushNativeTests.swift",
    "Tests/P2BluetoothScenesHost/HostNativeTests.swift",
    "Tests/P2Bluetooth/P2BluetoothNativeTests.swift",
    "Tests/P2Scenes/P2ScenesNativeTests.swift",
    "Tests/P2AR/P2ARNativeTests.swift",
    "Tests/P2Appearance/P2AppearanceNativeTests.swift",
    "Tests/P2WidgetLocalization/P2WidgetLocalizationNativeTests.swift",
    "Tests/JibunKitCoreTests/AugmentedReality/MiniAppARSessionAdapterTests.swift",
    "Tests/P2Action/P2ActionProbe.swift",
    "Tests/P2Action/P2ActionNativeTests.swift",
    "Sources/JibunKitIncomingExtensionUI/MiniAppIncomingExtensionViewController.swift",
    "Sources/JibunKitAction/ActionViewController.swift",
)

UI_EXPECTED_SOURCES = (
    "Tests/P2SceneRestorationUI/P2SceneRestorationAdmissionUITests.swift",
    "Tests/P2WidgetLocalization/P2OSSurfaceUITests.swift",
    "Tests/PackageWidgets/WidgetGallerySupport.swift",
)
COLD_UI_EXPECTED_SOURCES = (
    "Tests/P2LocationColdOSUI/P2LocationColdOSUITests.swift",
)

EXPECTED_REGISTRY_IDS = (
    "p2-background-a", "p2-background-b",
    "p2-location-tracker", "p2-location-regions",
    "p2-identity-a", "p2-identity-b",
    "p2-push-alpha", "p2-push-beta",
    "p2-bluetooth-sensor", "p2-bluetooth-accessory",
    "p2-scene-a", "p2-scene-b", "p2-ar",
    "p2-appearance-a", "p2-appearance-b",
    "incoming-a", "incoming-b",
)

BACKGROUND_MODES = ("fetch", "processing", "location", "remote-notification", "bluetooth-central")
BG_TASK_IDENTIFIERS = (
    "com.jibunkit.app.p2-background-a.ordinary",
    "com.jibunkit.app.p2-background-b.ordinary",
    "com.jibunkit.app.p2-background.shared-refresh",
    "com.jibunkit.app.p2-background-a.export.*",
    "com.jibunkit.app.p2-background-b.export.*",
)
PROJECT_FILES = (
    "Project.swift",
    "Sources/JibunKit/MiniAppRegistry.swift",
    "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift",
)


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one combined P2 host anchor: {old}")
    return text.replace(old, new, 1)


def diagnostic_destination(host, relative):
    source = Path(relative)
    if source.parts[:2] == ("Tests", "TemplateIntegration"):
        family = "TemplateIntegration"
    else:
        family = source.parts[1]
    return host / "Sources/JibunKit/P2CombinedDiagnostics" / family / source.name


def prepare(host):
    host = host.resolve()
    required = (APP_EXPECTED_SOURCES + NATIVE_EXPECTED_SOURCES + UI_EXPECTED_SOURCES
                + COLD_UI_EXPECTED_SOURCES + PROJECT_FILES)
    for relative in required:
        if not (host / relative).is_file():
            raise ValueError(f"Missing combined P2 host file: {relative}")
    if len(EXPECTED_REGISTRY_IDS) != len(set(EXPECTED_REGISTRY_IDS)):
        raise ValueError("Combined P2 expected registry IDs are not unique")

    changes = {}
    for relative in APP_EXPECTED_SOURCES:
        source = host / relative
        target = diagnostic_destination(host, relative)
        if target.exists():
            raise ValueError(f"Combined P2 app fixture destination already exists: {target}")
        changes[target] = source.read_text(encoding="utf-8")

    requirements = host / PROJECT_FILES[2]
    task_ids = "\n".join(f'                "{value}",' for value in BG_TASK_IDENTIFIERS)
    text = once(
        requirements.read_text(encoding="utf-8"),
        "public static let app = FeatureBuildConfiguration()",
        f'''public static let app = FeatureBuildConfiguration(features: [
        FeatureBuildRequirement(owner: "p2-background-probe", infoPlist: [
            "NSAppTransportSecurity": ["NSAllowsLocalNetworking": true],
            "NSLocalNetworkUsageDescription": "所有者別の背景転送をローカルHTTPで検証します。",
            "UIBackgroundModes": ["fetch", "processing"],
            "BGTaskSchedulerPermittedIdentifiers": [
{task_ids}
            ],
        ], localizedInfoPlist: [
            "en": ["NSLocalNetworkUsageDescription": "Uses local HTTP to verify owner-scoped background transfers."],
            "ja": ["NSLocalNetworkUsageDescription": "所有者別の背景転送をローカルHTTPで検証します。"],
        ]),
        FeatureBuildRequirement(owner: "p2-location-probe", infoPlist: [
            "NSLocationWhenInUseUsageDescription": "位置更新とRegionの検証で位置を使用します。",
            "NSLocationAlwaysAndWhenInUseUsageDescription": "背景のRegion配送を検証します。",
            "UIBackgroundModes": ["location"],
        ], localizedInfoPlist: [
            "en": [
                "NSLocationWhenInUseUsageDescription": "Uses your location to verify location updates and regions.",
                "NSLocationAlwaysAndWhenInUseUsageDescription": "Uses your location to verify background region delivery.",
            ],
            "ja": [
                "NSLocationWhenInUseUsageDescription": "位置更新とRegionの検証で位置を使用します。",
                "NSLocationAlwaysAndWhenInUseUsageDescription": "背景のRegion配送を検証します。",
            ],
        ]),
        FeatureBuildRequirement(owner: "p2-push-probe", infoPlist: [
            "UIBackgroundModes": ["remote-notification"],
        ]),
        FeatureBuildRequirement(owner: "p2-bluetooth-scenes-probe", infoPlist: [
            "NSBluetoothAlwaysUsageDescription": "BLE owner isolation diagnostics",
            "UIBackgroundModes": ["bluetooth-central"],
            "UIApplicationSceneManifest": ["UIApplicationSupportsMultipleScenes": true],
        ], localizedInfoPlist: [
            "en": ["NSBluetoothAlwaysUsageDescription": "Uses Bluetooth to verify BLE owner isolation."],
            "ja": ["NSBluetoothAlwaysUsageDescription": "BLEの所有者分離を検証するためBluetoothを使用します。"],
        ]),
        FeatureBuildRequirement(owner: "p2-ar-probe", infoPlist: [
            "NSCameraUsageDescription": "AR検証でカメラを使用します。",
        ], localizedInfoPlist: [
            "en": ["NSCameraUsageDescription": "Use the camera for the foreground AR feature."],
            "ja": ["NSCameraUsageDescription": "前景のAR機能でカメラを使用します。"],
        ]),
    ])''',
    )
    changes[requirements] = once(
        text,
        "public static let action: FeatureBuildConfiguration? = nil",
        "public static let action: FeatureBuildConfiguration? = FeatureBuildConfiguration()",
    )

    registry = host / PROJECT_FILES[1]
    registry_prefix = (
        "[P2BackgroundProbe.definitions, P2LocationProbe.definitions, "
        "P2IdentityProbe.definitions, P2PushProbe.definitions, "
        "P2BluetoothProbe.definitions, P2ScenesProbe.definitions, "
        "P2ARProbe.definitions, P2AppearanceProbe.definitions, "
        "P1IncomingProbe.definitions].flatMap { $0 } + ["
    )
    changes[registry] = once(
        registry.read_text(encoding="utf-8"),
        "static let all = makeRegistry([",
        "static let all = makeRegistry(" + registry_prefix,
    )

    # Swift rejects duplicate basenames in one module, even from separate
    # directories. The existing family host tests all use HostNativeTests.swift.
    native_sources = []
    for relative in NATIVE_EXPECTED_SOURCES:
        source = Path(relative)
        if sum(Path(item).name == source.name for item in NATIVE_EXPECTED_SOURCES) > 1:
            destination = host / "GeneratedFeatureTests/P2Combined" / (source.parent.name + source.name)
            if destination.exists():
                raise ValueError(f"Combined P2 native destination already exists: {destination}")
            changes[destination] = (host / relative).read_text(encoding="utf-8")
            native_sources.append(destination.relative_to(host).as_posix())
        else:
            native_sources.append(relative)
    if len({Path(item).name for item in native_sources}) != len(native_sources):
        raise ValueError("Combined P2 native source basenames collide")
    project = host / PROJECT_FILES[0]
    sources = ", ".join(f'"{path}"' for path in native_sources)
    text = once(
        project.read_text(encoding="utf-8"),
        "    targets: [\n",
        "    targets: [\n"
        '        .target(name: "P2LocationColdOSUITests", destinations: .iOS, product: .uiTests,\n'
        '            bundleId: "com.jibunkit.p2-location-cold-ui-tests", deploymentTargets: .iOS("26.0"),\n'
        '            infoPlist: .default, sources: ["Tests/P2LocationColdOSUI/P2LocationColdOSUITests.swift"],\n'
        '            dependencies: [.target(name: "JibunKit-App")]),\n'
        '        .target(name: "P2CombinedOSUITests", destinations: .iOS, product: .uiTests,\n'
        '            bundleId: "com.jibunkit.p2-combined-ui-tests", deploymentTargets: .iOS("26.0"),\n'
        '            infoPlist: .default, sources: ["Tests/P2WidgetLocalization/P2OSSurfaceUITests.swift", "Tests/PackageWidgets/WidgetGallerySupport.swift", "Tests/P2SceneRestorationUI/P2SceneRestorationAdmissionUITests.swift"],\n'
        '            dependencies: [.target(name: "JibunKit-App")]),\n'
        '        .target(name: "P2CombinedNativeTests", destinations: .iOS, product: .unitTests,\n'
        '            bundleId: "com.jibunkit.p2-combined-tests", deploymentTargets: .iOS("26.0"),\n'
        f"            infoPlist: .default, sources: [{sources}],\n"
        '            dependencies: [.target(name: "JibunKit-App"), .package(product: "JibunKitCore")]),\n',
    )
    changes[project] = once(
        text,
        "    schemes: [\n",
        "    schemes: [\n"
        '        .scheme(name: "P2LocationColdOSUITests", shared: true,\n'
        '            buildAction: .buildAction(targets: ["JibunKit-App"]),\n'
        '            testAction: .targets(["P2LocationColdOSUITests"], configuration: .debug)),\n'
        '        .scheme(name: "P2CombinedOSUITests", shared: true,\n'
        '            buildAction: .buildAction(targets: ["JibunKit-App"]),\n'
        '            testAction: .targets(["P2CombinedOSUITests"], configuration: .debug)),\n'
        '        .scheme(name: "P2CombinedNativeTests", shared: true,\n'
        '            buildAction: .buildAction(targets: ["JibunKit-App"]),\n'
        '            testAction: .targets(["P2CombinedNativeTests"], configuration: .debug)),\n',
    )

    for target, content in changes.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    prepare(parser.parse_args().host)
