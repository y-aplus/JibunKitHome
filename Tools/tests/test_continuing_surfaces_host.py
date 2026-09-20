import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("continuing_host", ROOT / "Tools/prepare-continuing-surfaces-host.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ContinuingHostTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for name in ["Package.swift", "Project.swift", "Sources/JibunKit/MiniAppRegistry.swift",
                     "Sources/JibunKitWidget/CounterWidget.swift", "Tests/ContinuingSurfaces/ContinuingProbe.swift",
                     "Tests/ContinuingSurfaces/ContinuingHostUITests.swift",
                     "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift"]:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        for name in MODULE.MODULES:
            family = "ContinuingAlarms" if "Alarm" in name else "ContinuingLiveActivities"
            target = root / f"Tests/{family}/{name[-1]}/Sources/{name}/Feature.swift"
            target.parent.mkdir(parents=True)
            target.write_text("import JibunKitCore\n", encoding="utf-8")
        return root

    def test_all_four_modules_enter_app_and_widget_with_existing_features_retained(self):
        root = self.fixture()
        MODULE.prepare(root)
        project = (root / "Project.swift").read_text(encoding="utf-8")
        for name in MODULE.MODULES:
            self.assertEqual(project.count(f'.package(product: "{name}")'), 3)
        self.assertIn('sources: ["Tests/ContinuingSurfaces/ContinuingStateNativeTests.swift"]', project)
        self.assertIn('testAction: .targets(["ContinuingStateNativeTests"]', project)
        self.assertIn('"NSSupportsLiveActivities": true', project)
        self.assertNotIn('"NSAlarmKitUsageDescription"', project)
        requirements = (root / "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift").read_text(encoding="utf-8")
        self.assertIn('"NSAlarmKitUsageDescription": "ミニアプリで設定した予定やタイマーを知らせます。"', requirements)
        self.assertIn('"en": ["NSAlarmKitUsageDescription": "Notifies you about schedules and timers set by mini apps."]', requirements)
        self.assertIn('"ja": ["NSAlarmKitUsageDescription": "ミニアプリで設定した予定やタイマーを知らせます。"]', requirements)
        self.assertIn('.target(name: "JibunKitShare-Extension")', project)
        registry = (root / "Sources/JibunKit/MiniAppRegistry.swift").read_text(encoding="utf-8")
        self.assertIn("ContinuingProbe.definitions + [", registry)
        self.assertIn("CounterMiniApp.definition", registry)
        self.assertIn("ReminderMiniApp.definition", registry)
        self.assertIn("externalAccess: MiniAppWindowOwnership.externalAccess(for: definition)", registry)
        widget = (root / "Sources/JibunKitWidget/CounterWidget.swift").read_text(encoding="utf-8")
        self.assertEqual(widget.count("        CounterWidget()"), 1)
        self.assertIn("FeatureBAlarmLiveActivity()", widget)
        self.assertTrue((root / "UITests/ContinuingHostUITests.swift").exists())

    def test_missing_module_or_changed_anchor_never_partially_rewrites_host(self):
        for failure in ["module", "anchor", "repeat"]:
            with self.subTest(failure=failure):
                root = self.fixture()
                if failure == "module":
                    next(root.glob("Tests/ContinuingAlarms/A/Sources/*/Feature.swift")).unlink()
                elif failure == "anchor":
                    (root / "Project.swift").write_text("different project\n", encoding="utf-8")
                else:
                    MODULE.prepare(root)
                before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
                with self.assertRaises(ValueError):
                    MODULE.prepare(root)
                self.assertEqual(before, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})

    def test_helper_module_dependency_is_preserved_without_cross_owner_dependency(self):
        root = self.fixture()
        helper = root / "Tests/ContinuingAlarms/Support/Sources/ContinuingAlarmSupport/Support.swift"
        helper.parent.mkdir(parents=True)
        helper.write_text("import JibunKitCore\n", encoding="utf-8")
        feature = next(root.glob("Tests/ContinuingAlarms/A/Sources/*/Feature.swift"))
        feature.write_text("import JibunKitCore\nimport ContinuingAlarmSupport\n", encoding="utf-8")
        MODULE.prepare(root)
        package = (root / "Package.swift").read_text(encoding="utf-8")
        declaration = next(line for line in package.splitlines() if '.target(name: "ContinuingAlarmFeatureA"' in line)
        self.assertIn('"ContinuingAlarmSupport"', declaration)
        self.assertNotIn('"ContinuingAlarmFeatureB"', declaration)
        self.assertIn('.target(name: "ContinuingAlarmSupport"', package)
