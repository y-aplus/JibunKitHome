"""Build/test a combined native Feature host and package one diagnostic IPA.

No camera, microphone, lock-screen command, or background behavior is inferred
from simulator success. The result explicitly leaves those device checks open.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import time


def require_test_passes(report, summary, sources):
    expected = []
    for source in sources:
        classes = re.findall(r"\bclass\s+(\w+)\s*:\s*(?:XCTestCase|WidgetGalleryTestCase)", source)
        methods = re.findall(r"\bfunc\s+(test\w+)\s*\(", source)
        if len(classes) != 1 or not methods or len(methods) != len(set(methods)):
            raise ValueError("Expected one XCTestCase with unique test methods per media test source")
        expected.extend((classes[0], method) for method in methods)
    if not expected or len(expected) != len(set(expected)):
        raise ValueError("Missing or duplicate media tests")
    cases = []
    def visit(nodes):
        for node in nodes:
            if node.get("nodeType") == "Test Case":
                identity = node.get("nodeIdentifier", "").split("/")
                if len(identity) < 2:
                    raise ValueError("Test case has no class/method identifier")
                cases.append((identity[-2], identity[-1].removesuffix("()"), node.get("result")))
            else:
                visit(node.get("children", []))
    visit(report.get("testNodes", []))
    for name, method in expected:
        actual = [status for cls, test, status in cases if (cls, test) == (name, method)]
        if actual != ["Passed"]:
            raise ValueError(f"Expected one actual passing test: {name}.{method}: {actual}")
    if (summary.get("result") != "Passed" or summary.get("failedTests") != 0
            or summary.get("skippedTests") != 0 or summary.get("passedTests") != len(expected)
            or len(cases) != len(expected)):
        raise ValueError("Native media summary contains failure, skip, missing or unexpected tests")
    return [f"{name}.{method}" for name, method in expected]


def check_requirements(info, surface="media"):
    if surface not in {"media", "background-location", "identity-push", "ble-scenes", "ar-action", "p2-combined"}:
        raise ValueError("Unknown native host surface")
    descriptions = (["NSCameraUsageDescription", "NSBluetoothAlwaysUsageDescription", "NSLocalNetworkUsageDescription", "NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"] if surface == "p2-combined" else ["NSCameraUsageDescription"] if surface == "ar-action" else ["NSBluetoothAlwaysUsageDescription"] if surface == "ble-scenes" else [] if surface == "identity-push" else ["NSCameraUsageDescription", "NSMicrophoneUsageDescription"] if surface == "media"
                    else ["NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"])
    for key in descriptions:
        if not isinstance(info.get(key), str) or not info[key].strip():
            raise ValueError(f"Missing media usage description: {key}")
    modes = {"fetch", "processing", "location", "remote-notification", "bluetooth-central"} if surface == "p2-combined" else set() if surface == "ar-action" else {"bluetooth-central"} if surface == "ble-scenes" else {"remote-notification"} if surface == "identity-push" else {"audio"} if surface == "media" else {"fetch", "processing", "location"}
    if not modes <= set(info.get("UIBackgroundModes", [])):
        raise ValueError("Missing required background modes")
    if surface in {"ble-scenes", "p2-combined"} and info.get("UIApplicationSceneManifest", {}).get("UIApplicationSupportsMultipleScenes") is not True:
        raise ValueError("Multiple window scene support is required")
    if surface in {"background-location", "p2-combined"}:
        required = {"com.jibunkit.app.p2-background-a.ordinary",
                    "com.jibunkit.app.p2-background-b.ordinary",
                    "com.jibunkit.app.p2-background.shared-refresh",
                    "com.jibunkit.app.p2-background-a.export.*",
                    "com.jibunkit.app.p2-background-b.export.*"}
        if set(info.get("BGTaskSchedulerPermittedIdentifiers", [])) != required:
            raise ValueError("Background task identifiers differ from the diagnostic contract")
    if info.get("CFBundleIdentifier") != "com.jibunkit.app":
        raise ValueError("Diagnostic app identity changed")



def check_localized_usage_descriptions(app, info):
    """Read the built app resources, not the generator's input dictionaries."""
    keys = [key for key in info if key.startswith("NS") and key.endswith("UsageDescription")]
    if not keys:
        return []
    for language in ("en", "ja"):
        path = app / f"{language}.lproj/InfoPlist.strings"
        values = plistlib.loads(path.read_bytes())
        for key in keys:
            value = values.get(key)
            if not isinstance(value, str) or not value.strip() or value == key:
                raise ValueError(f"Missing built {language} permission description: {key}")
    widget = app / "PlugIns/JibunKitWidget_Extension.appex"
    for language in ("en", "ja"):
        path = widget / f"{language}.lproj/InfoPlist.strings"
        values = plistlib.loads(path.read_bytes())
        if any(key in values for key in keys):
            raise ValueError("App permission descriptions leaked into the Widget target")
    return keys


def require_english_simulator_language(output):
    """WidgetKit follows the Simulator OS language, not host launch arguments."""
    languages = re.findall(r"[A-Za-z]+(?:[-_][A-Za-z]+)?", output)
    if not languages or languages[0].lower().split("-")[0].split("_")[0] != "en":
        raise ValueError(f"P2 OS UI requires an English disposable Simulator: {output!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-id", required=True)
    parser.add_argument("--surface", choices=["media", "background-location", "identity-push", "ble-scenes", "ar-action", "p2-combined"], default="media")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    is_media = args.surface == "media"
    families = {"media": ["MediaAudio", "MediaCapture", "MediaIntegration"],
                "background-location": ["P2Background", "P2Location"],
                "identity-push": ["P2Identity", "P2Push"], "ble-scenes": ["P2Bluetooth", "P2Scenes"], "ar-action": ["P2AR", "P2Action", "P2Appearance"], "p2-combined": ["P2Background", "P2Location", "P2Identity", "P2Push", "P2Bluetooth", "P2Scenes", "P2AR", "P2Action", "P2Appearance"]}[args.surface]
    label = {"media": "Media", "background-location": "BackgroundLocation", "identity-push": "IdentityPush", "ble-scenes": "BluetoothScenes", "ar-action": "ARAction", "p2-combined": "P2Combined"}[args.surface]
    scheme = label + "NativeTests"
    evidence = Path(os.environ["RUNNER_TEMP"]) / label
    evidence.mkdir(exist_ok=True)
    source = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    started = time.monotonic()
    timings = []

    def run(command, cwd, label, limit=900):
        remaining = 24 * 60 - (time.monotonic() - started)
        if remaining <= 0:
            raise TimeoutError("Native host validation exhausted its 24 minute step budget")
        begin, output, code = time.monotonic(), "", None
        try:
            result = subprocess.run([str(value) for value in command], cwd=cwd,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=min(limit, remaining))
            output, code = result.stdout, result.returncode
            result.check_returncode()
            return output
        except subprocess.TimeoutExpired as error:
            output = error.stdout or ""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            raise
        finally:
            (evidence / f"{label}.log").write_text(output, encoding="utf-8")
            timings.append({"label": label, "seconds": round(time.monotonic() - begin, 3), "exit_code": code})
            (evidence / "timings.json").write_text(json.dumps(timings, indent=2) + "\n", encoding="utf-8")
            print(output, end="", flush=True)

    result = {"source": source, "surface": args.surface, "passed": False,
              "physical_os_actions": "not exercised; grouped device verification required"}
    try:
        with tempfile.TemporaryDirectory(prefix=f"jibunkit-{args.surface}-") as temporary:
            root = Path(temporary)
            # Ignored local Features, data and worktree-private files stay out.
            names = subprocess.check_output(["git", "ls-files", "-z"], cwd=repo).decode().split("\0")
            for name in filter(None, names):
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(repo / name, destination)
            prepare = f"prepare-{args.surface}-host.py"
            run(["python3", root / "Tools" / prepare, "--host", root], root, "prepare")
            run(["tuist", "generate", "--no-open"], root, "generate")
            derived = root / "Build"
            common = ["-workspace", "JibunKit.xcworkspace", "-derivedDataPath", derived]
            native_error = None
            timeouts = ([] if is_media else ["-test-timeouts-enabled", "YES",
                "-default-test-execution-time-allowance", "60",
                "-maximum-test-execution-time-allowance", "240" if args.surface in {"identity-push", "ble-scenes", "ar-action", "p2-combined"} else "120"])
            try:
                command = ["xcodebuild", "test", *common, "-scheme", scheme,
                       "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
                       "-resultBundlePath", evidence / "native-tests.xcresult",
                       f"-only-testing:{scheme}", "-parallel-testing-enabled", "NO",
                       *timeouts,
                       "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual"]
                if args.surface in {"background-location", "identity-push", "ble-scenes", "p2-combined"}:
                    command = ["python3", root / "Tests/Fixtures/network_server.py", "--run-command", *command]
                run(command, root, "native-tests")
            except subprocess.CalledProcessError as error:
                native_error = error
            finally:
                # Console output can be interleaved with AVFoundation diagnostics.
                # Export structured results even on failure; retain the original error.
                for section in ["tests", "summary"]:
                    try:
                        output = run(["xcrun", "xcresulttool", "get", "test-results", section,
                                      "--path", evidence / "native-tests.xcresult"], root,
                                     f"test-{section}", limit=60)
                        (evidence / f"test-{section}.json").write_text(output, encoding="utf-8")
                    except Exception as export_error:
                        result[f"{section}_export_error"] = str(export_error)
            if native_error is not None:
                try:
                    run(["xcrun", "xcresulttool", "export", "diagnostics", "--path",
                         evidence / "native-tests.xcresult", "--output-path", evidence / "crash-diagnostics"],
                        root, "export-diagnostics", limit=90)
                except Exception as export_error:
                    result["diagnostics_export_error"] = str(export_error)
                raise native_error
            result["tests"] = require_test_passes(
                json.loads((evidence / "test-tests.json").read_text(encoding="utf-8")),
                json.loads((evidence / "test-summary.json").read_text(encoding="utf-8")), [

                (root / f"Tests/{family}/{family}NativeTests.swift").read_text(encoding="utf-8")
                for family in families] + (
                    [(root / "Tests/P2IdentityPushHost/HostNativeTests.swift").read_text(encoding="utf-8")]
                    if args.surface == "identity-push" else
                    [(root / "Tests/P2BluetoothScenesHost/HostNativeTests.swift").read_text(encoding="utf-8")]
                    if args.surface == "ble-scenes" else
                    [(root / path).read_text(encoding="utf-8") for path in [
                        "Tests/JibunKitCoreTests/AugmentedReality/MiniAppARSessionAdapterTests.swift",
                        "Tests/P2WidgetLocalization/P2WidgetLocalizationNativeTests.swift"]]
                    if args.surface == "ar-action" else
                    [(root / path).read_text(encoding="utf-8") for path in [
                        "Tests/JibunKitCoreTests/AugmentedReality/MiniAppARSessionAdapterTests.swift",
                        "Tests/P2WidgetLocalization/P2WidgetLocalizationNativeTests.swift",
                        "Tests/P2IdentityPushHost/HostNativeTests.swift",
                        "Tests/P2BluetoothScenesHost/HostNativeTests.swift",
                        "Tests/P2CombinedHost/HostNativeTests.swift"]]
                    if args.surface == "p2-combined" else []))
            run(["xcodebuild", "build", *common, "-scheme", "JibunKit-App",
                 "-configuration", "Release", "-destination", "generic/platform=iOS",
                 "CODE_SIGNING_ALLOWED=NO"], root, "release-build")
            app = derived / "Build/Products/Release-iphoneos/JibunKit_App.app"
            info = plistlib.loads((app / "Info.plist").read_bytes())
            check_requirements(info, args.surface)
            result["localized_usage_descriptions"] = check_localized_usage_descriptions(app, info)
            shutil.copyfile(app / "Info.plist", evidence / "app-Info.plist")

            def entitlement(name):
                matches = list((root / "Derived").rglob(name))
                if len(matches) != 1:
                    raise ValueError(f"Expected one entitlement file: {name}: {matches}")
                return matches[0]

            run(["codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der",
                 "--entitlements", entitlement("JibunKitWidget-Extension.entitlements"),
                 app / "PlugIns/JibunKitWidget_Extension.appex"], root, "sign-widget")
            run(["python3", root / "Tools/verify-share-extension.py", "--app", app,
                 "--entitlements-root", root / "Derived"], root, "sign-share")
            if args.surface in {"ar-action", "p2-combined"}:
                run(["python3", root / "Tools/verify-share-extension.py", "--app", app,
                     "--kind", "Action", "--entitlements-root", root / "Derived"], root, "sign-action")
            run(["codesign", "--force", "--sign", "-", "--timestamp=none", "--generate-entitlement-der",
                 "--entitlements", entitlement("JibunKit-App.entitlements"), app], root, "sign-app")
            run(["codesign", "--verify", "--deep", "--strict", app], root, "verify-signatures")
            payload = root / "Package/Payload"
            payload.mkdir(parents=True)
            run(["ditto", app, payload / "JibunKit.app"], root, "copy-payload")
            ipa = evidence / {"media": "JibunKit-P2-C-check.ipa", "background-location": "JibunKit-P2-B-check.ipa",
                              "identity-push": "JibunKit-P2-I-check.ipa", "ble-scenes": "JibunKit-P2-S-check.ipa", "ar-action": "JibunKit-P2-AR-Action-check.ipa", "p2-combined": "JibunKit-P2-combined-check.ipa"}[args.surface]
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", "Payload", ipa], payload.parent, "package")
            run(["unzip", "-t", ipa], root, "ipa-crc")
            run(["shasum", "--algorithm", "256", ipa], root, "ipa-sha256")
            # Preserve a verified diagnostic IPA even if a later OS UI experiment
            # fails. Overall success still requires every named test to pass.
            result["ipa_packaged"] = True
            if args.surface == "p2-combined":
                locale = run(["xcrun", "simctl", "spawn", args.simulator_id, "defaults", "read",
                              "NSGlobalDomain", "AppleLanguages"], root,
                             "simulator-languages", limit=60)
                require_english_simulator_language(locale)
                # Reset only this app's camera decision. Do not erase unrelated
                # privacy state, and let XCUITest observe the actual OS prompt.
                run(["xcrun", "simctl", "privacy", args.simulator_id, "reset", "camera",
                     "com.jibunkit.app"], root, "reset-camera-privacy", limit=60)
                run(["xcrun", "simctl", "privacy", args.simulator_id, "grant", "location-always",
                     "com.jibunkit.app"], root, "grant-location-privacy", limit=60)
                run(["xcodebuild", "test", *common, "-scheme", "P2CombinedOSUITests",
                     "-configuration", "Debug",
                     "-destination", f"platform=iOS Simulator,id={args.simulator_id}",
                     "-resultBundlePath", evidence / "os-ui-tests.xcresult",
                     "-only-testing:P2CombinedOSUITests",
                     "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=YES",
                     "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual"], root, "os-ui-tests")
                ui_summary = json.loads(run([
                    "xcrun", "xcresulttool", "get", "test-results", "summary",
                    "--path", evidence / "os-ui-tests.xcresult"], root,
                    "os-ui-summary", limit=60))
                (evidence / "os-ui-summary.json").write_text(
                    json.dumps(ui_summary, indent=2), encoding="utf-8")
                ui_tests = json.loads(run([
                    "xcrun", "xcresulttool", "get", "test-results", "tests",
                    "--path", evidence / "os-ui-tests.xcresult"], root,
                    "os-ui-cases", limit=60))
                (evidence / "os-ui-cases.json").write_text(
                    json.dumps(ui_tests, indent=2), encoding="utf-8")
                result["os_ui_passed_tests"] = require_test_passes(ui_tests, ui_summary, [
                    (root / name).read_text(encoding="utf-8") for name in [
                        "Tests/P2WidgetLocalization/P2OSSurfaceUITests.swift",
                        "Tests/P2SceneRestorationUI/P2SceneRestorationAdmissionUITests.swift"]])
                result["simulator_os_ui"] = {
                    "widget": "English Counter gallery preview and home rendering",
                    "camera": "English system permission purpose text",
                    "windows": "two distinct owner sessions restored, then one destroyed",
                    "location": "background standard update plus foreground geofence enter/exit callbacks",
                    "physical_device": "not exercised",
                }
            result["passed"] = True
    except Exception as error:
        result["error"] = str(error)
        raise
    finally:
        (evidence / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
