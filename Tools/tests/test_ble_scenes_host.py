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

HOST = load("ble_scenes_host", "Tools/prepare-ble-scenes-host.py")
VERIFY = load("native_feature_verifier", "Tools/verify-media.py")

class BluetoothScenesHostTests(unittest.TestCase):
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
        target = root / "Tests/P2BluetoothScenesHost/HostNativeTests.swift"
        target.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / "Tests/P2BluetoothScenesHost/HostNativeTests.swift", target)
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
            copied = root / "Sources/JibunKit/BluetoothScenesDiagnostics" / family
            self.assertTrue((copied / f"{family}Probe.swift").is_file())
            self.assertFalse((copied / f"{family}NativeTests.swift").exists())
        registry = (root / "Sources/JibunKit/MiniAppRegistry.swift").read_text(encoding="utf-8")
        for entry in ["P2BluetoothProbe.definitions", "P2ScenesProbe.definitions",
                      "CounterMiniApp.definition", "ReminderMiniApp.definition"]:
            self.assertIn(entry, registry)
        self.assertIn("BluetoothScenesNativeTests", project)
        requirements = (root / "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift").read_text(encoding="utf-8")
        self.assertIn('"en": ["NSBluetoothAlwaysUsageDescription": "Uses Bluetooth to verify BLE owner isolation."]', requirements)
        self.assertIn('"ja": ["NSBluetoothAlwaysUsageDescription": "BLEの所有者分離を検証するためBluetoothを使用します。"]', requirements)

    def test_invalid_source_layout_is_rejected_before_any_write(self):
        for fault in ["missing", "test-in-app", "anchor", "repeat"]:
            with self.subTest(fault=fault):
                root = self.fixture()
                if fault == "missing":
                    (root / "Tests/P2Scenes/P2ScenesNativeTests.swift").unlink()
                elif fault == "test-in-app":
                    (root / "Tests/P2Scenes/Wrong.swift").write_text("import XCTest\n")
                elif fault == "anchor":
                    (root / "Project.swift").write_text("invalid\n")
                else:
                    HOST.prepare(root)
                before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
                with self.assertRaises(ValueError):
                    HOST.prepare(root)
                self.assertEqual(before, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})

    def test_diagnostic_requires_bluetooth_and_multiple_scene_declarations(self):
        info = {"CFBundleIdentifier": "com.jibunkit.app",
                "NSBluetoothAlwaysUsageDescription": "BLE diagnostics",
                "UIBackgroundModes": ["bluetooth-central"],
                "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": True}}
        VERIFY.check_requirements(info, "ble-scenes")
        for key in info:
            broken = dict(info)
            del broken[key]
            with self.assertRaises(ValueError):
                VERIFY.check_requirements(broken, "ble-scenes")
        root = self.fixture()
        HOST.prepare(root)
        generated = (root / "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift").read_text(encoding="utf-8")
        self.assertIn('"bluetooth-central"', generated)
        self.assertIn('"UIApplicationSupportsMultipleScenes": true', generated)
