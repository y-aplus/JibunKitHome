import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ar_action_host", ROOT / "Tools/prepare-ar-action-host.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ARActionHostTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for relative in MODULE.PROJECT_FILES:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        for relative in MODULE.REQUIRED_SOURCES:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            source = ROOT / relative
            if source.is_file():
                shutil.copyfile(source, target)
            else:
                target.write_text("// fixture\n", encoding="utf-8")
        return root

    def snapshot(self, root):
        return {path.relative_to(root): path.read_bytes() for path in root.rglob("*") if path.is_file()}

    def test_ar_registration_action_opt_in_and_combined_native_target_are_generated(self):
        root = self.fixture()
        project_before = (root / "Project.swift").read_text(encoding="utf-8")

        MODULE.prepare(root)

        project = (root / "Project.swift").read_text(encoding="utf-8")
        registry = (root / "Sources/JibunKit/MiniAppRegistry.swift").read_text(encoding="utf-8")
        requirements = (root / MODULE.PROJECT_FILES[2]).read_text(encoding="utf-8")
        self.assertIn("P2ARProbe.definitions + P2AppearanceProbe.definitions + P1IncomingProbe.definitions + [", registry)
        self.assertNotIn("P2ActionProbe", registry)
        self.assertTrue((root / "Sources/JibunKit/ARActionDiagnostics/P2AR/P2ARProbe.swift").is_file())
        self.assertTrue((root / "Sources/JibunKit/ARActionDiagnostics/TemplateIntegration/P1IncomingProbe.swift").is_file())
        self.assertIn('"NSCameraUsageDescription": "AR検証でカメラを使用します。"', requirements)
        self.assertIn("public static let action: FeatureBuildConfiguration? = FeatureBuildConfiguration()", requirements)
        self.assertIn('name: "ARActionNativeTests"', project)
        for relative in MODULE.NATIVE_SOURCES:
            self.assertIn(f'"{relative}"', project)
        self.assertNotIn('"Tests/TemplateIntegration/P1IncomingProbe.swift"', project)
        self.assertIn('name: "IncomingNativeTests"', project)
        self.assertIn('name: "MigrationUITests"', project)
        self.assertIn('name: "CounterExample"', project)
        self.assertIn('bundleId: "com.jibunkit.app"', project)
        self.assertIn('bundleId: "com.jibunkit.app"', project_before)

    def test_missing_file_and_multiple_anchor_fail_before_any_write(self):
        for mode in ("missing", "multiple-project-anchor", "multiple-requirement-anchor"):
            with self.subTest(mode=mode):
                root = self.fixture()
                if mode == "missing":
                    (root / "Tests/P2Action/P2ActionProbe.swift").unlink()
                elif mode == "multiple-project-anchor":
                    project = root / "Project.swift"
                    project.write_text(project.read_text(encoding="utf-8") + "\n    schemes: [\n", encoding="utf-8")
                else:
                    requirements = root / MODULE.PROJECT_FILES[2]
                    requirements.write_text(
                        requirements.read_text(encoding="utf-8")
                        + "\npublic static let action: FeatureBuildConfiguration? = nil\n",
                        encoding="utf-8",
                    )
                before = self.snapshot(root)
                with self.assertRaises(ValueError):
                    MODULE.prepare(root)
                self.assertEqual(before, self.snapshot(root))


if __name__ == "__main__":
    unittest.main()
