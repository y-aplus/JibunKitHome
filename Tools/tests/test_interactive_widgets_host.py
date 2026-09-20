import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("interactive_host", ROOT / "Tools/prepare-interactive-widgets-host.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class InteractiveHostTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for name in ["Package.swift", "Project.swift", "Sources/JibunKit/MiniAppRegistry.swift",
                     "Sources/JibunKitWidget/CounterWidget.swift", "Tests/InteractiveWidgets/InteractiveProbe.swift",
                     "Tests/InteractiveWidgets/InteractiveManagementUITests.swift"]:
            destination = root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        return root

    def test_prepared_host_keeps_existing_widget_share_and_generic_management(self):
        root = self.fixture()
        MODULE.prepare(root)
        widget = (root / "Sources/JibunKitWidget/CounterWidget.swift").read_text(encoding="utf-8")
        self.assertEqual(widget.count("        CounterWidget()"), 1)
        for owner in "AB":
            self.assertIn(f"        Feature{owner}Control()", widget)
            self.assertIn(f"        Feature{owner}Widget()", widget)
        registry = (root / "Sources/JibunKit/MiniAppRegistry.swift").read_text(encoding="utf-8")
        self.assertIn("externalAccess: MiniAppWindowOwnership.externalAccess(for: definition)", registry)
        self.assertIn("CounterMiniApp.definition", registry)
        self.assertIn("ReminderMiniApp.definition", registry)
        project = (root / "Project.swift").read_text(encoding="utf-8")
        self.assertIn('.target(name: "JibunKitShare-Extension")', project)
        self.assertEqual(project.count('.package(product: "InteractiveFeatureA")'), 2)
        self.assertTrue((root / "UITests/InteractiveManagementUITests.swift").is_file())

    def test_missing_anchor_does_not_partially_mutate_host(self):
        root = self.fixture()
        registry = root / "Sources/JibunKit/MiniAppRegistry.swift"
        registry.write_text("changed registry shape\n")
        before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
        with self.assertRaisesRegex(ValueError, "anchor"):
            MODULE.prepare(root)
        self.assertEqual(before, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})

    def test_duplicate_preparation_is_rejected_without_changes(self):
        root = self.fixture()
        MODULE.prepare(root)
        before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
        with self.assertRaises(ValueError):
            MODULE.prepare(root)
        self.assertEqual(before, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})
