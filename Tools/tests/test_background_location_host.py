import importlib.util
from pathlib import Path
import re
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

HOST = load("background_location_host", "Tools/prepare-background-location-host.py")
VERIFY = load("native_feature_verifier", "Tools/verify-media.py")

class BackgroundLocationHostTests(unittest.TestCase):
    def fixture(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        for name in ["Project.swift", "Sources/JibunKit/MiniAppRegistry.swift",
                     "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift"]:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        for family in HOST.FAMILIES:
            shutil.copytree(ROOT / "Tests" / family, root / "Tests" / family)
        return root

    def test_actual_fixture_sources_join_one_host_with_unchanged_identity(self):
        root = self.fixture()
        before = (root / "Project.swift").read_text(encoding="utf-8")
        HOST.prepare(root)
        project = (root / "Project.swift").read_text(encoding="utf-8")
        identity = r'(?:bundleId: |"CFBundle(?:ShortVersionString|Version)": )"[^"]+"'
        for value in re.findall(identity, before):
            self.assertIn(value, project)
        for family in HOST.FAMILIES:
            self.assertIn(f'Tests/{family}/{family}NativeTests.swift', project)
            copied = root / "Sources/JibunKit/BackgroundLocationDiagnostics" / family
            self.assertTrue((copied / f"{family}Probe.swift").is_file())
            self.assertFalse((copied / f"{family}NativeTests.swift").exists())
        registry = (root / "Sources/JibunKit/MiniAppRegistry.swift").read_text(encoding="utf-8")
        for entry in ["P2BackgroundProbe.definitions", "P2LocationProbe.definitions",
                      "CounterMiniApp.definition", "ReminderMiniApp.definition"]:
            self.assertIn(entry, registry)
        self.assertIn("BackgroundLocationNativeTests", project)
        requirements = (root / "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift").read_text(encoding="utf-8")
        self.assertIn('"en": ["NSLocalNetworkUsageDescription"', requirements)
        self.assertIn('"ja": ["NSLocalNetworkUsageDescription"', requirements)
        self.assertIn('"NSLocationWhenInUseUsageDescription": "Uses your location to verify location updates and regions."', requirements)
        self.assertIn('"NSLocationAlwaysAndWhenInUseUsageDescription": "背景のRegion配送を検証します。"', requirements)

    def test_invalid_source_layout_is_rejected_before_any_write(self):
        for fault in ["missing", "test-in-app", "anchor", "repeat"]:
            with self.subTest(fault=fault):
                root = self.fixture()
                if fault == "missing":
                    (root / "Tests/P2Location/P2LocationNativeTests.swift").unlink()
                elif fault == "test-in-app":
                    (root / "Tests/P2Location/Wrong.swift").write_text("import XCTest\n")
                elif fault == "anchor":
                    (root / "Project.swift").write_text("invalid\n")
                else:
                    HOST.prepare(root)
                before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
                with self.assertRaises(ValueError):
                    HOST.prepare(root)
                self.assertEqual(before, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})

    def test_built_plist_requires_all_modes_permissions_and_exact_scheduler_ids(self):
        info = {"CFBundleIdentifier": "com.jibunkit.app",
                "NSLocationWhenInUseUsageDescription": "foreground",
                "NSLocationAlwaysAndWhenInUseUsageDescription": "background",
                "UIBackgroundModes": ["fetch", "processing", "location"],
                "BGTaskSchedulerPermittedIdentifiers": [
                    "com.jibunkit.app.p2-background-a.ordinary",
                    "com.jibunkit.app.p2-background-b.ordinary",
                    "com.jibunkit.app.p2-background.shared-refresh",
                    "com.jibunkit.app.p2-background-a.export.*",
                    "com.jibunkit.app.p2-background-b.export.*"]}
        VERIFY.check_requirements(info, "background-location")
        for key in info:
            broken = dict(info)
            del broken[key]
            with self.assertRaises(ValueError):
                VERIFY.check_requirements(broken, "background-location")
        info["BGTaskSchedulerPermittedIdentifiers"].append("unexpected.owner")
        with self.assertRaises(ValueError):
            VERIFY.check_requirements(info, "background-location")
