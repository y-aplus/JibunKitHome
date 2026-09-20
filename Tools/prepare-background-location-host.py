"""Connect background and location probe families to a disposable copy of the normal host.

This prepares source only. It does not claim a native build or device result.
Validate all fixture files and source anchors before changing the copy.
"""
import argparse
from pathlib import Path
import re


FAMILIES = ("P2Background", "P2Location")


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one background/location host anchor: {old}")
    return text.replace(old, new, 1)


def prepare(host):
    host = host.resolve()
    changes = {}
    test_sources = []
    for family in FAMILIES:
        directory = host / "Tests" / family
        for filename in [f"{family}Probe.swift", f"{family}NativeTests.swift"]:
            if not (directory / filename).is_file():
                raise ValueError(f"Missing background/location fixture: {family}/{filename}")
        for source in sorted(directory.rglob("*.swift")):
            content = source.read_text(encoding="utf-8")
            if source.name == f"{family}NativeTests.swift":
                test_sources.append(source.relative_to(host).as_posix())
                continue
            if re.search(r"^\s*(?:@testable\s+)?import\s+(?:XCTest|Testing)\b", content, re.M):
                raise ValueError(f"Test-only source would enter the diagnostic app: {source}")
            target = host / "Sources/JibunKit/BackgroundLocationDiagnostics" / family / source.relative_to(directory)
            if target.exists():
                raise ValueError(f"Background/location fixture destination already exists: {target}")
            changes[target] = content

    requirements = host / "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift"
    changes[requirements] = once(requirements.read_text(encoding="utf-8"),
        "public static let app = FeatureBuildConfiguration()",
        '''public static let app = FeatureBuildConfiguration(features: [
        FeatureBuildRequirement(owner: "p2-background-probe", infoPlist: [
            "NSAppTransportSecurity": ["NSAllowsLocalNetworking": true],
            "NSLocalNetworkUsageDescription": "所有者別の背景転送をローカルHTTPで検証します。",
            "UIBackgroundModes": ["fetch", "processing"],
            "BGTaskSchedulerPermittedIdentifiers": [
                "com.jibunkit.app.p2-background-a.ordinary",
                "com.jibunkit.app.p2-background-b.ordinary",
                "com.jibunkit.app.p2-background.shared-refresh",
                "com.jibunkit.app.p2-background-a.export.*",
                "com.jibunkit.app.p2-background-b.export.*",
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
    ])''')

    registry = host / "Sources/JibunKit/MiniAppRegistry.swift"
    changes[registry] = once(registry.read_text(encoding="utf-8"),
        "static let all = makeRegistry([",
        "static let all = makeRegistry(P2BackgroundProbe.definitions + P2LocationProbe.definitions + [")
    project = host / "Project.swift"
    sources = ", ".join(f'"{path}"' for path in test_sources)
    text = once(project.read_text(encoding="utf-8"), "    targets: [\n", "    targets: [\n"
        '        .target(name: "BackgroundLocationNativeTests", destinations: .iOS, product: .unitTests,\n'
        '            bundleId: "com.jibunkit.background-location-tests", deploymentTargets: .iOS("26.0"),\n'
        f'            infoPlist: .default, sources: [{sources}],\n'
        '            dependencies: [.target(name: "JibunKit-App"), .package(product: "JibunKitCore")]),\n')
    changes[project] = once(text, "    schemes: [\n", "    schemes: [\n"
        '        .scheme(name: "BackgroundLocationNativeTests", shared: true,\n'
        '            buildAction: .buildAction(targets: ["JibunKit-App"]),\n'
        '            testAction: .targets(["BackgroundLocationNativeTests"], configuration: .debug)),\n')
    for target, content in changes.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    prepare(parser.parse_args().host)
