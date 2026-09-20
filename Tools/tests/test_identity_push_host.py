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

HOST = load("identity_push_host", "Tools/prepare-identity-push-host.py")
VERIFY = load("native_feature_verifier", "Tools/verify-media.py")

class IdentityPushHostTests(unittest.TestCase):
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
        target = root / "Tests/P2IdentityPushHost/HostNativeTests.swift"
        target.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / "Tests/P2IdentityPushHost/HostNativeTests.swift", target)
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
            copied = root / "Sources/JibunKit/IdentityPushDiagnostics" / family
            self.assertTrue((copied / f"{family}Probe.swift").is_file())
            self.assertFalse((copied / f"{family}NativeTests.swift").exists())
        registry = (root / "Sources/JibunKit/MiniAppRegistry.swift").read_text(encoding="utf-8")
        for entry in ["P2IdentityProbe.definitions", "P2PushProbe.definitions",
                      "CounterMiniApp.definition", "ReminderMiniApp.definition"]:
            self.assertIn(entry, registry)
        self.assertIn("IdentityPushNativeTests", project)

    def test_invalid_source_layout_is_rejected_before_any_write(self):
        for fault in ["missing", "test-in-app", "anchor", "repeat"]:
            with self.subTest(fault=fault):
                root = self.fixture()
                if fault == "missing":
                    (root / "Tests/P2Push/P2PushNativeTests.swift").unlink()
                elif fault == "test-in-app":
                    (root / "Tests/P2Push/Wrong.swift").write_text("import XCTest\n")
                elif fault == "anchor":
                    (root / "Project.swift").write_text("invalid\n")
                else:
                    HOST.prepare(root)
                before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
                with self.assertRaises(ValueError):
                    HOST.prepare(root)
                self.assertEqual(before, {p: p.read_bytes() for p in root.rglob("*") if p.is_file()})

    def test_diagnostic_requires_background_mode_without_claiming_signing(self):
        info = {"CFBundleIdentifier": "com.jibunkit.app", "UIBackgroundModes": ["remote-notification"]}
        VERIFY.check_requirements(info, "identity-push")
        for key in info:
            broken = dict(info)
            del broken[key]
            with self.assertRaises(ValueError):
                VERIFY.check_requirements(broken, "identity-push")
        root = self.fixture()
        HOST.prepare(root)
        generated = (root / "Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift").read_text(encoding="utf-8")
        self.assertNotIn('"aps-environment"', generated)
        self.assertNotIn('"com.apple.developer.icloud-container-identifiers"', generated)
