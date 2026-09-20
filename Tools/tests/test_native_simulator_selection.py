"""Exercise the actual native workflow selector against installed-runtime fixtures."""
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class NativeSimulatorSelectionTests(unittest.TestCase):
    def select(self, major, requested, devices, surface="media"):
        workflow = (ROOT / '.github/workflows/native-surface.yml').read_text(encoding='utf-8')
        code = textwrap.dedent(workflow.split("<<'PY'\n", 1)[1].split('\n          PY', 1)[0])
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary) / 'simulators.json'
            fixture.write_text(json.dumps({'devices': devices}), encoding='utf-8')
            result = io.StringIO()
            with patch.dict(os.environ, {'IOS_MAJOR': major, 'REQUESTED_RUNTIME': requested, 'SURFACE': surface}), \
                    patch.object(sys, 'argv', ['selector', str(fixture)]), redirect_stdout(result):
                exec(compile(code, 'workflow-selector', 'exec'), {})
            return result.getvalue().strip()

    @staticmethod
    def runtime(version, device_id, available=True):
        return {'com.apple.CoreSimulator.SimRuntime.iOS-' + version:
                [{'name': 'iPhone 17', 'udid': device_id, 'isAvailable': available}]}

    def testKeepsMajorsSeparateAndHonorsExactRuntime(self):
        devices = self.runtime('26-4', 'old') | self.runtime('26-5', 'current') | self.runtime('27-0', 'new')
        self.assertEqual(self.select('26', '', devices), 'current')
        self.assertEqual(self.select('26', '26.4', devices), 'old')
        self.assertEqual(self.select('27', '', devices), 'new')
        self.assertEqual(self.select('27', '27.0', devices), 'new')

    def testMissingOrWrongMajorNeverFallsBackToAnotherOS(self):
        devices = self.runtime('26-5', 'current')
        for major, requested in [('27', ''), ('26', '27.0'), ('26', '26.4')]:
            with self.subTest(major=major, requested=requested), self.assertRaises(SystemExit):
                self.select(major, requested, devices)

    def testUnavailableDeviceIsRejected(self):
        with self.assertRaises(SystemExit):
            self.select('27', '', self.runtime('27-0', 'unavailable', False))

    def testSceneSurfaceRequiresIPadAndDoesNotFallBackToPhone(self):
        devices = self.runtime('26-5', 'phone')
        with self.assertRaises(SystemExit):
            self.select('26', '', devices, 'ble-scenes')
        devices['com.apple.CoreSimulator.SimRuntime.iOS-26-5'].append(
            {'name': 'iPad Air', 'udid': 'pad', 'isAvailable': True})
        self.assertEqual(self.select('26', '', devices, 'ble-scenes'), 'pad')
        self.assertEqual(self.select('26', '', devices, 'location-cold'), 'pad')
        self.assertEqual(self.select('26', '', devices), 'phone')

    def testColdLocationWorkflowIsIsolatedAndReportsUnobserved(self):
        workflow = (ROOT / '.github/workflows/native-surface.yml').read_text(encoding='utf-8')
        cold = workflow.split('            location-cold)', 1)[1].split('              ;;', 1)[0]
        self.assertIn('-scheme P2LocationColdOSUITests', cold)
        self.assertIn('-only-testing:P2LocationColdOSUITests/', cold)
        self.assertIn("outcome = 'unobserved-skip'", cold)
        self.assertIn('-maximum-test-execution-time-allowance 240', cold)
        self.assertNotIn('verify-media.py', cold)
        self.assertLess(cold.index('xcodebuild build-for-testing'), cold.index('simctl install'))
        self.assertLess(cold.index('simctl install'), cold.index('grant location-always'))
        self.assertLess(cold.index('grant location-always'), cold.index('xcodebuild test-without-building'))

    def testUnavailableIPadIsNotARealWindowTestDevice(self):
        devices = {'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
            {'name': 'iPad Air', 'udid': 'pad', 'isAvailable': False}]}
        with self.assertRaises(SystemExit):
            self.select('26', '', devices, 'ble-scenes')
