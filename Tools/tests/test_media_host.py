import importlib.util
from pathlib import Path
import re
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("media_host", ROOT / "Tools/prepare-media-host.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MediaHostTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for name in ["Project.swift", "Sources/JibunKit/MiniAppRegistry.swift",
                     "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift"]:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        for family in MODULE.FAMILIES:
            directory = root / "Tests" / family
            directory.mkdir(parents=True)
            (directory / f"{family}Probe.swift").write_text("import JibunKitCore\n", encoding="utf-8")
            (directory / f"{family}NativeTests.swift").write_text("import XCTest\n", encoding="utf-8")
        return root

    def test_both_features_and_tests_are_connected_without_changing_production_identity(self):
        root = self.fixture()
        before = (root / "Project.swift").read_text(encoding="utf-8")
        MODULE.prepare(root)
        project = (root / "Project.swift").read_text(encoding="utf-8")
        self.assertIn('bundleId: "com.jibunkit.app"', project)
        self.assertEqual(re.findall(r'"CFBundle(?:ShortVersionString|Version)": "[^"]+"', before),
                         re.findall(r'"CFBundle(?:ShortVersionString|Version)": "[^"]+"', project))
        for family in MODULE.FAMILIES:
            self.assertIn(f'Tests/{family}/{family}NativeTests.swift', project)
            target = root / "Sources/JibunKit/MediaDiagnostics" / family
            self.assertTrue((target / f"{family}Probe.swift").is_file())
            self.assertFalse((target / f"{family}NativeTests.swift").exists())
        registry = (root / "Sources/JibunKit/MiniAppRegistry.swift").read_text(encoding="utf-8")
        self.assertIn("MediaIntegrationProbe.definitions + [", registry)
        self.assertIn("CounterMiniApp.definition", registry)
        self.assertIn("ReminderMiniApp.definition", registry)
        requirements = (root / "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift").read_text(encoding="utf-8")
        self.assertEqual(requirements.count('"NSMicrophoneUsageDescription"'), 6)
        self.assertEqual(requirements.count('"Uses the microphone to verify audio and capture behavior."'), 2)
        self.assertEqual(requirements.count('"en": ['), 2)
        self.assertEqual(requirements.count('"ja": ['), 2)
        self.assertIn('"NSCameraUsageDescription": "Uses the camera to verify capture, document scanning, and code scanning."', requirements)
        self.assertIn('"UIBackgroundModes": ["audio"]', requirements)
        self.assertIn('public static let widget = FeatureBuildConfiguration()', requirements)

    def test_missing_test_changed_anchor_and_accidental_test_in_app_fail_before_writes(self):
        for mode in ["missing", "anchor", "test-in-app", "repeat"]:
            with self.subTest(mode=mode):
                root = self.fixture()
                if mode == "missing":
                    (root / "Tests/MediaCapture/MediaCaptureNativeTests.swift").unlink()
                elif mode == "anchor":
                    (root / "Project.swift").write_text("changed\n", encoding="utf-8")
                elif mode == "test-in-app":
                    (root / "Tests/MediaAudio/OtherTest.swift").write_text("import XCTest\n", encoding="utf-8")
                else:
                    MODULE.prepare(root)
                before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
                with self.assertRaises(ValueError):
                    MODULE.prepare(root)
                self.assertEqual(before, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})
