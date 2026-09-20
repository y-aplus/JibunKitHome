"""Inject both P2-L Feature pairs into a disposable copy of the normal host."""
import argparse
from pathlib import Path
import re


MODULES = ["ContinuingFeatureA", "ContinuingFeatureB",
           "ContinuingAlarmFeatureA", "ContinuingAlarmFeatureB"]


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one continuing host anchor: {old}")
    return text.replace(old, new, 1)


def fixture_modules(host):
    result = {}
    for family in ["ContinuingLiveActivities", "ContinuingAlarms"]:
        for sources in (host / "Tests" / family).rglob("Sources"):
            for module in sources.iterdir():
                if not module.is_dir() or not list(module.rglob("*.swift")):
                    continue
                if module.name in result:
                    raise ValueError(f"Duplicate fixture module: {module.name}")
                if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", module.name):
                    raise ValueError(f"Invalid fixture module: {module.name}")
                result[module.name] = module
    missing = set(MODULES) - result.keys()
    if missing:
        raise ValueError(f"Missing reviewed fixture modules: {sorted(missing)}")
    return result


def prepare(host):
    host = host.resolve()
    modules = fixture_modules(host)
    changes = {}
    products = "".join(f'        .library(name: "{m}", targets: ["{m}"]),\n' for m in MODULES)
    targets = []
    for name, path in sorted(modules.items()):
        imports = set()
        for source in path.rglob("*.swift"):
            imports.update(re.findall(r"^import (\w+)", source.read_text(encoding="utf-8"), re.M))
        dependencies = sorted((imports & (modules.keys() | {"JibunKitCore", "JibunKitBackup"})) - {name})
        dependency_text = ", ".join(f'"{d}"' for d in dependencies)
        targets.append(f'        .target(name: "{name}", dependencies: [{dependency_text}], '
                       f'path: "{path.relative_to(host).as_posix()}"),\n')
    package = host / "Package.swift"
    text = once(package.read_text(encoding="utf-8"), "    products: [\n", "    products: [\n" + products)
    changes[package] = once(text, "    targets: [\n", "    targets: [\n" + "".join(targets))

    requirements = host / "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift"
    changes[requirements] = once(requirements.read_text(encoding="utf-8"),
        "public static let app = FeatureBuildConfiguration()",
        '''public static let app = FeatureBuildConfiguration(features: [
        FeatureBuildRequirement(owner: "p2-continuing-alarm-probe", infoPlist: [
            "NSAlarmKitUsageDescription": "ミニアプリで設定した予定やタイマーを知らせます。",
        ], localizedInfoPlist: [
            "en": ["NSAlarmKitUsageDescription": "Notifies you about schedules and timers set by mini apps."],
            "ja": ["NSAlarmKitUsageDescription": "ミニアプリで設定した予定やタイマーを知らせます。"],
        ]),
    ])''')

    project = host / "Project.swift"
    text = project.read_text(encoding="utf-8")
    text = once(text, 'let appBuild = try EnabledFeatureBuildRequirements.app.compose(infoPlist: [',
        'let appBuild = try EnabledFeatureBuildRequirements.app.compose(infoPlist: [\n'
        '    "NSSupportsLiveActivities": true,')
    dependencies = "".join(f', .package(product: "{m}")' for m in MODULES)
    text = once(text, '.target(name: "JibunKitShare-Extension")',
                '.target(name: "JibunKitShare-Extension")' + dependencies)
    text = once(text,
        'entitlements: .dictionary(widgetBuild.entitlements),\n            dependencies: [.package(product: "CounterFeature"), .package(product: "JibunKitCore")]',
        'entitlements: .dictionary(widgetBuild.entitlements),\n            dependencies: [.package(product: "CounterFeature"), .package(product: "JibunKitCore")' + dependencies + ']')
    text = once(text, '    targets: [\n', '    targets: [\n'
        '        .target(name: "ContinuingStateNativeTests", destinations: .iOS, product: .unitTests,\n'
        '            bundleId: "com.jibunkit.continuing-state-tests", deploymentTargets: .iOS("26.0"),\n'
        '            infoPlist: .default, sources: ["Tests/ContinuingSurfaces/ContinuingStateNativeTests.swift"],\n'
        '            dependencies: [.target(name: "JibunKit-App"), .package(product: "JibunKitCore")'
        + dependencies + ']),\n')
    changes[project] = once(text, '    schemes: [\n', '    schemes: [\n'
        '        .scheme(name: "ContinuingStateNativeTests", shared: true,\n'
        '            buildAction: .buildAction(targets: ["JibunKit-App"]),\n'
        '            testAction: .targets(["ContinuingStateNativeTests"], configuration: .debug)),\n')

    registry = host / "Sources/JibunKit/MiniAppRegistry.swift"
    changes[registry] = once(registry.read_text(encoding="utf-8"),
        'static let all = makeRegistry([', 'static let all = makeRegistry(ContinuingProbe.definitions + [')
    widget = host / "Sources/JibunKitWidget/CounterWidget.swift"
    imports = "\n".join(f"import {m}" for m in MODULES)
    packages = "FeatureAIntents.self, FeatureBIntents.self, FeatureAAlarmIntents.self, FeatureBAlarmIntents.self"
    text = once(widget.read_text(encoding="utf-8"), 'import CounterFeature',
        'import CounterFeature\nimport AppIntents\n' + imports + '\n\n'
        'struct ContinuingWidgetIntents: AppIntentsPackage {\n'
        f'    static var includedPackages: [any AppIntentsPackage.Type] {{ [{packages}] }}\n}}')
    changes[widget] = once(text, '        CounterWidget()',
        '        CounterWidget()\n        FeatureALiveActivityWidget()\n        FeatureBLiveActivityWidget()\n'
        '        FeatureAAlarmLiveActivity()\n        FeatureBAlarmLiveActivity()')
    for filename, destination in [("ContinuingProbe.swift", "Sources/JibunKit"),
                                  ("ContinuingHostUITests.swift", "UITests")]:
        changes[host / destination / filename] = (host / "Tests/ContinuingSurfaces" / filename).read_text(encoding="utf-8")
    # No partial mutation when a shared source anchor or module is unavailable.
    for path, content in changes.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    prepare(parser.parse_args().host)
