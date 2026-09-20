"""Connect AR and Action probes to a disposable copy of the normal host.

This prepares source only. It does not claim a native build or device result.
Validate every fixture file and source anchor before changing the copy.
"""
import argparse
from pathlib import Path


APP_SOURCES = (
    "Tests/P2AR/P2ARProbe.swift",
    "Tests/P2Appearance/P2AppearanceProbe.swift",
    "Tests/TemplateIntegration/P1IncomingProbe.swift",
)
NATIVE_SOURCES = (
    "Tests/P2AR/P2ARNativeTests.swift",
    "Tests/P2Appearance/P2AppearanceNativeTests.swift",
    "Tests/P2WidgetLocalization/P2WidgetLocalizationNativeTests.swift",
    "Tests/JibunKitCoreTests/AugmentedReality/MiniAppARSessionAdapterTests.swift",
    "Tests/P2Action/P2ActionProbe.swift",
    "Tests/P2Action/P2ActionNativeTests.swift",
    "Sources/JibunKitIncomingExtensionUI/MiniAppIncomingExtensionViewController.swift",
    "Sources/JibunKitAction/ActionViewController.swift",
)
REQUIRED_SOURCES = APP_SOURCES + NATIVE_SOURCES
PROJECT_FILES = (
    "Project.swift",
    "Sources/JibunKit/MiniAppRegistry.swift",
    "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift",
)


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one AR/Action host anchor: {old}")
    return text.replace(old, new, 1)


def prepare(host):
    host = host.resolve()
    for relative in REQUIRED_SOURCES + PROJECT_FILES:
        if not (host / relative).is_file():
            raise ValueError(f"Missing AR/Action host file: {relative}")

    changes = {}
    for relative in APP_SOURCES:
        source = host / relative
        target = host / "Sources/JibunKit/ARActionDiagnostics" / source.parent.name / source.name
        if target.exists():
            raise ValueError(f"AR/Action app fixture destination already exists: {target}")
        changes[target] = source.read_text(encoding="utf-8")

    requirements = host / PROJECT_FILES[2]
    text = once(
        requirements.read_text(encoding="utf-8"),
        "public static let app = FeatureBuildConfiguration()",
        '''public static let app = FeatureBuildConfiguration(features: [
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
    changes[registry] = once(
        registry.read_text(encoding="utf-8"),
        "static let all = makeRegistry([",
        "static let all = makeRegistry(P2ARProbe.definitions + P2AppearanceProbe.definitions + P1IncomingProbe.definitions + [",
    )

    project = host / PROJECT_FILES[0]
    sources = ", ".join(f'"{path}"' for path in NATIVE_SOURCES)
    text = once(
        project.read_text(encoding="utf-8"),
        "    targets: [\n",
        "    targets: [\n"
        '        .target(name: "ARActionNativeTests", destinations: .iOS, product: .unitTests,\n'
        '            bundleId: "com.jibunkit.ar-action-tests", deploymentTargets: .iOS("26.0"),\n'
        f"            infoPlist: .default, sources: [{sources}],\n"
        '            dependencies: [.target(name: "JibunKit-App"), .package(product: "JibunKitCore")]),\n',
    )
    changes[project] = once(
        text,
        "    schemes: [\n",
        "    schemes: [\n"
        '        .scheme(name: "ARActionNativeTests", shared: true,\n'
        '            buildAction: .buildAction(targets: ["JibunKit-App"]),\n'
        '            testAction: .targets(["ARActionNativeTests"], configuration: .debug)),\n',
    )

    for target, content in changes.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    prepare(parser.parse_args().host)
