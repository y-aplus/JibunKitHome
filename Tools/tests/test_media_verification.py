import importlib.util
from pathlib import Path
import unittest
import tempfile
import plistlib

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("media_verification", ROOT / "Tools/verify-media.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MediaVerificationTests(unittest.TestCase):
    sources = ["final class AudioTests: XCTestCase { func testOwner() {} }",
               "final class CaptureTests: XCTestCase { func testOwner() {} }"]
    def report(self):
        return {"testNodes": [{"nodeType": "Test Suite", "children": [
            {"nodeType": "Test Case", "nodeIdentifier": cls + "/testOwner()", "result": "Passed"}
            for cls in ["AudioTests", "CaptureTests"]]}]}

    def summary(self):
        return {"result": "Passed", "failedTests": 0, "skippedTests": 0, "passedTests": 2}

    def test_structured_pass_required_for_each_class(self):
        self.assertEqual(MODULE.require_test_passes(self.report(), self.summary(), self.sources),
                         ["AudioTests.testOwner", "CaptureTests.testOwner"])
        for change in ["missing", "duplicate", "skipped", "failed", "unknown"]:
            report = self.report(); nodes = report["testNodes"][0]["children"]
            if change == "missing": nodes.pop()
            elif change == "duplicate": nodes.append(dict(nodes[0]))
            else: nodes[1]["result"] = change.title()
            with self.assertRaises(ValueError):
                MODULE.require_test_passes(report, self.summary(), self.sources)
        for key, value in [("result", "Failed"), ("failedTests", 1), ("skippedTests", 1), ("passedTests", 1)]:
            summary = self.summary(); summary[key] = value
            with self.assertRaises(ValueError):
                MODULE.require_test_passes(self.report(), summary, self.sources)

    def test_os_ui_helper_subclass_requires_actual_named_pass(self):
        sources = ["final class AudioTests: WidgetGalleryTestCase { func testOwner() {} }",
                   "final class CaptureTests: XCTestCase { func testOwner() {} }"]
        self.assertEqual(len(MODULE.require_test_passes(self.report(), self.summary(), sources)), 2)
        report = self.report()
        report["testNodes"][0]["children"][0]["nodeIdentifier"] = "WrongClass/testOwner()"
        with self.assertRaises(ValueError):
            MODULE.require_test_passes(report, self.summary(), sources)

    def test_no_test_declarations_cannot_pass(self):
        for sources in [[], ["final class Empty: XCTestCase {}"]]:
            with self.assertRaises(ValueError):
                MODULE.require_test_passes(self.report(), self.summary(), sources)

    def test_built_app_must_have_usage_descriptions_and_background_audio(self):
        info = {"CFBundleIdentifier": "com.jibunkit.app", "NSCameraUsageDescription": "camera",
                "NSMicrophoneUsageDescription": "mic", "UIBackgroundModes": ["audio"]}
        MODULE.check_requirements(info)
        for key in info:
            broken = dict(info)
            del broken[key]
            with self.assertRaises(ValueError):
                MODULE.check_requirements(broken)

    def test_ar_requires_camera_but_no_background_capability(self):
        info = {"CFBundleIdentifier": "com.jibunkit.app", "NSCameraUsageDescription": "foreground AR"}
        MODULE.check_requirements(info, "ar-action")
        for description in [None, "", " "]:
            broken = dict(info, NSCameraUsageDescription=description)
            with self.assertRaises(ValueError):
                MODULE.check_requirements(broken, "ar-action")

    def test_permission_localization_requires_real_built_app_and_no_widget_leak(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            widget = app / "PlugIns/JibunKitWidget_Extension.appex"
            key = "NSCameraUsageDescription"
            for root in (app, widget):
                for language in ("en", "ja"):
                    path = root / f"{language}.lproj/InfoPlist.strings"
                    path.parent.mkdir(parents=True)
                    path.write_bytes(plistlib.dumps({key: "camera"} if root == app else {}))
            self.assertEqual(MODULE.check_localized_usage_descriptions(app, {key: "base"}), [key])
            (widget / "en.lproj/InfoPlist.strings").write_bytes(plistlib.dumps({key: "leaked"}))
            with self.assertRaisesRegex(ValueError, "leaked"):
                MODULE.check_localized_usage_descriptions(app, {key: "base"})
            (widget / "en.lproj/InfoPlist.strings").write_bytes(plistlib.dumps({}))
            (app / "ja.lproj/InfoPlist.strings").write_bytes(plistlib.dumps({}))
            with self.assertRaisesRegex(ValueError, "Missing built ja"):
                MODULE.check_localized_usage_descriptions(app, {key: "base"})

    def test_widget_os_ui_requires_existing_english_simulator_language(self):
        for value in ["(\n    en,\n    ja\n)", "(\n    en-US\n)"]:
            MODULE.require_english_simulator_language(value)
        for value in ["(\n    ja,\n    en\n)", "", "unexpected"]:
            with self.assertRaisesRegex(ValueError, "English disposable Simulator"):
                MODULE.require_english_simulator_language(value)

    def test_combined_requires_all_capabilities_and_exact_background_identifiers(self):
        info = {
            "CFBundleIdentifier": "com.jibunkit.app",
            "UIBackgroundModes": ["fetch", "processing", "location", "remote-notification", "bluetooth-central"],
            "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": True},
            "BGTaskSchedulerPermittedIdentifiers": [
                "com.jibunkit.app.p2-background-a.ordinary", "com.jibunkit.app.p2-background-b.ordinary",
                "com.jibunkit.app.p2-background.shared-refresh",
                "com.jibunkit.app.p2-background-a.export.*", "com.jibunkit.app.p2-background-b.export.*"],
        }
        keys = ["NSCameraUsageDescription", "NSBluetoothAlwaysUsageDescription", "NSLocalNetworkUsageDescription",
                "NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"]
        info.update({key: "purpose" for key in keys})
        MODULE.check_requirements(info, "p2-combined")
        for key in keys + ["UIApplicationSceneManifest", "BGTaskSchedulerPermittedIdentifiers"]:
            damaged = dict(info); damaged.pop(key)
            with self.assertRaises(ValueError):
                MODULE.check_requirements(damaged, "p2-combined")
        for mode in info["UIBackgroundModes"]:
            damaged = dict(info, UIBackgroundModes=[m for m in info["UIBackgroundModes"] if m != mode])
            with self.assertRaises(ValueError):
                MODULE.check_requirements(damaged, "p2-combined")
