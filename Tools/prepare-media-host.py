"""Connect both media probe families to a disposable copy of the normal host.

This prepares source only. It does not claim a native build or device result.
Validate all fixture files and source anchors before changing the copy.
"""
import argparse
from pathlib import Path
import re


FAMILIES = ("MediaAudio", "MediaCapture", "MediaIntegration")


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one media host anchor: {old}")
    return text.replace(old, new, 1)


def prepare(host):
    host = host.resolve()
    changes = {}
    test_sources = []
    for family in FAMILIES:
        directory = host / "Tests" / family
        for filename in [f"{family}Probe.swift", f"{family}NativeTests.swift"]:
            if not (directory / filename).is_file():
                raise ValueError(f"Missing media fixture: {family}/{filename}")
        for source in sorted(directory.rglob("*.swift")):
            content = source.read_text(encoding="utf-8")
            if source.name == f"{family}NativeTests.swift":
                test_sources.append(source.relative_to(host).as_posix())
                continue
            if re.search(r"^\s*(?:@testable\s+)?import\s+(?:XCTest|Testing)\b", content, re.M):
                raise ValueError(f"Test-only source would enter the diagnostic app: {source}")
            target = host / "Sources/JibunKit/MediaDiagnostics" / family / source.relative_to(directory)
            if target.exists():
                raise ValueError(f"Media fixture destination already exists: {target}")
            changes[target] = content

    requirements = host / "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift"
    changes[requirements] = once(requirements.read_text(encoding="utf-8"),
        "public static let app = FeatureBuildConfiguration()",
        '''public static let app = FeatureBuildConfiguration(features: [
        FeatureBuildRequirement(owner: "media-audio-probe", infoPlist: [
            "NSMicrophoneUsageDescription": "音声と撮影の検証でマイクを使用します。",
            "UIBackgroundModes": ["audio"],
        ], localizedInfoPlist: [
            "en": ["NSMicrophoneUsageDescription": "Uses the microphone to verify audio and capture behavior."],
            "ja": ["NSMicrophoneUsageDescription": "音声と撮影の検証でマイクを使用します。"],
        ]),
        FeatureBuildRequirement(owner: "media-capture-probe", infoPlist: [
            "NSCameraUsageDescription": "撮影と文書・コード読取りの検証でカメラを使用します。",
            "NSMicrophoneUsageDescription": "音声と撮影の検証でマイクを使用します。",
        ], localizedInfoPlist: [
            "en": [
                "NSCameraUsageDescription": "Uses the camera to verify capture, document scanning, and code scanning.",
                "NSMicrophoneUsageDescription": "Uses the microphone to verify audio and capture behavior.",
            ],
            "ja": [
                "NSCameraUsageDescription": "撮影と文書・コード読取りの検証でカメラを使用します。",
                "NSMicrophoneUsageDescription": "音声と撮影の検証でマイクを使用します。",
            ],
        ]),
    ])''')

    registry = host / "Sources/JibunKit/MiniAppRegistry.swift"
    changes[registry] = once(registry.read_text(encoding="utf-8"),
        "static let all = makeRegistry([",
        "static let all = makeRegistry(MediaIntegrationProbe.definitions + [")
    project = host / "Project.swift"
    sources = ", ".join(f'"{path}"' for path in test_sources)
    text = once(project.read_text(encoding="utf-8"), "    targets: [\n", "    targets: [\n"
        '        .target(name: "MediaNativeTests", destinations: .iOS, product: .unitTests,\n'
        '            bundleId: "com.jibunkit.media-tests", deploymentTargets: .iOS("26.0"),\n'
        f'            infoPlist: .default, sources: [{sources}],\n'
        '            dependencies: [.target(name: "JibunKit-App"), .package(product: "JibunKitCore")]),\n')
    changes[project] = once(text, "    schemes: [\n", "    schemes: [\n"
        '        .scheme(name: "MediaNativeTests", shared: true,\n'
        '            buildAction: .buildAction(targets: ["JibunKit-App"]),\n'
        '            testAction: .targets(["MediaNativeTests"], configuration: .debug)),\n')
    for target, content in changes.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, required=True)
    prepare(parser.parse_args().host)
