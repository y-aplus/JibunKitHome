import importlib.util
from pathlib import Path
import shutil
import re
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("p2_combined_host", ROOT / "Tools/prepare-p2-combined-host.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class P2CombinedHostTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for relative in MODULE.PROJECT_FILES:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        for relative in (MODULE.APP_EXPECTED_SOURCES + MODULE.NATIVE_EXPECTED_SOURCES
                         + MODULE.UI_EXPECTED_SOURCES + MODULE.COLD_UI_EXPECTED_SOURCES):
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            source = ROOT / relative
            if source.is_file():
                shutil.copyfile(source, target)
            else:
                self.fail(f"Missing real combined fixture source: {relative}")
        return root

    def snapshot(self, root):
        return {path.relative_to(root): path.read_bytes() for path in root.rglob("*") if path.is_file()}

    def test_all_diagnostics_are_composed_once(self):
        root = self.fixture()
        MODULE.prepare(root)

        requirements = (root / MODULE.PROJECT_FILES[2]).read_text(encoding="utf-8")
        registry = (root / MODULE.PROJECT_FILES[1]).read_text(encoding="utf-8")
        project = (root / MODULE.PROJECT_FILES[0]).read_text(encoding="utf-8")
        self.assertEqual(len(MODULE.EXPECTED_REGISTRY_IDS), len(set(MODULE.EXPECTED_REGISTRY_IDS)))
        for value in MODULE.BACKGROUND_MODES + MODULE.BG_TASK_IDENTIFIERS:
            self.assertEqual(requirements.count(f'"{value}"'), 1)
        for key in ["NSLocalNetworkUsageDescription", "NSLocationWhenInUseUsageDescription",
                    "NSLocationAlwaysAndWhenInUseUsageDescription", "NSBluetoothAlwaysUsageDescription",
                    "NSCameraUsageDescription"]:
            self.assertGreaterEqual(requirements.count(f'"{key}"'), 3)
        self.assertIn("public static let action: FeatureBuildConfiguration? = FeatureBuildConfiguration()", requirements)
        for probe in ["P2BackgroundProbe", "P2LocationProbe", "P2IdentityProbe", "P2PushProbe",
                      "P2BluetoothProbe", "P2ScenesProbe", "P2ARProbe", "P2AppearanceProbe",
                      "P1IncomingProbe"]:
            self.assertEqual(registry.count(probe + ".definitions"), 1)
        self.assertNotIn("P2ActionProbe.definitions", registry)
        self.assertIn('name: "P2CombinedNativeTests"', project)
        self.assertIn('name: "P2CombinedOSUITests"', project)
        self.assertIn('name: "P2LocationColdOSUITests"', project)
        self.assertIn('Tests/P2LocationColdOSUI/P2LocationColdOSUITests.swift', project)
        source_list = re.search(
            r'name: "P2CombinedNativeTests".*?infoPlist: \.default, sources: \[(.*?)\]',
            project, re.DOTALL).group(1)
        compiled = re.findall(r'"([^"]+)"', source_list)
        self.assertEqual(len(compiled), len(MODULE.NATIVE_EXPECTED_SOURCES))
        self.assertEqual(len(compiled), len({Path(item).name for item in compiled}))
        actual_bytes = sorted((root / item).read_text(encoding="utf-8") for item in compiled)
        expected_bytes = sorted((root / item).read_text(encoding="utf-8") for item in MODULE.NATIVE_EXPECTED_SOURCES)
        self.assertEqual(actual_bytes, expected_bytes)
        self.assertNotIn('"Tests/P2AR/P2ARProbe.swift"', project)
        self.assertNotIn('"Tests/P2Appearance/P2AppearanceProbe.swift"', project)
        self.assertNotIn('"Tests/TemplateIntegration/P1IncomingProbe.swift"', project)
        for relative in MODULE.APP_EXPECTED_SOURCES:
            self.assertTrue(MODULE.diagnostic_destination(root, relative).is_file())

    def test_missing_duplicate_and_repeat_fail_before_writes(self):
        cases = (
            ("missing", ""),
            ("project-target", "    targets: [\n"),
            ("project-scheme", "    schemes: [\n"),
            ("registry", "static let all = makeRegistry(["),
            ("requirements", "public static let app = FeatureBuildConfiguration()"),
            ("action", "public static let action: FeatureBuildConfiguration? = nil"),
            ("repeat", ""),
        )
        for mode, duplicate in cases:
            with self.subTest(mode=mode):
                root = self.fixture()
                if mode == "missing":
                    (root / MODULE.NATIVE_EXPECTED_SOURCES[0]).unlink()
                elif mode == "repeat":
                    MODULE.prepare(root)
                else:
                    relative = MODULE.PROJECT_FILES[1] if mode == "registry" else (
                        MODULE.PROJECT_FILES[2] if mode in {"requirements", "action"} else MODULE.PROJECT_FILES[0]
                    )
                    target = root / relative
                    target.write_text(target.read_text(encoding="utf-8") + "\n" + duplicate + "\n", encoding="utf-8")
                before = self.snapshot(root)
                with self.assertRaises(ValueError):
                    MODULE.prepare(root)
                self.assertEqual(before, self.snapshot(root))


if __name__ == "__main__":
    unittest.main()
