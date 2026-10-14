import base64
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid

from morph_lab import simulator
from morph_lab.scenario import LabError


class SimulatorCaptureTests(unittest.TestCase):
    def test_both_sides_share_payload_and_have_distinct_capture_manifests(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "capture"
            container = root / "container"
            for name in ("Documents/rec-lab.jsonl", "tmp/morph-lab.jsonl"):
                path = container / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('{"k":"lab_start"}\n')
            udid = str(uuid.uuid4())
            scenario = {"id": "paired", "appearance": "light"}
            payloads, sides = [], []

            def command(args, **kwargs):
                args = [str(arg) for arg in args]
                if args[:4] == ["xcrun", "simctl", "list", "devices"]:
                    return json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0":
                                                   [{"udid": udid, "state": "Booted"}]}})
                if args[:3] == ["flutter", "build", "ios"]:
                    payload = next(arg.split("=", 2)[2] for arg in args if arg.startswith("--dart-define=MORPH_LAB_SCENARIO="))
                    payloads.append(json.loads(base64.b64decode(payload)))
                    self.assertIn("--simulator", args)
                if "test-without-building" in args:
                    sides.append(kwargs["env"]["TEST_RUNNER_PROBE_LAB_SIDE"])
                    self.assertEqual(json.loads(kwargs["env"]["TEST_RUNNER_PROBE_LAB_JSON"]), scenario)
                if "get_app_container" in args:
                    return str(container)
                if "attachments" in args:
                    shots = Path(args[args.index("--output-path") + 1])
                    shots.mkdir()
                    (shots / "events.json").write_text('[{"k":"lab_environment","rm":false,"rt":false}]')
                return ""

            with patch.object(simulator, "command", side_effect=command), patch.object(simulator, "provenance", return_value={"schema": 1}):
                simulator.capture_simulator(scenario, output, udid, side="both")
            self.assertEqual(payloads, [scenario])
            self.assertEqual(sides, ["native", "flutter"])
            for side in sides:
                manifest = json.loads((output / side / "manifest.json").read_text())
                self.assertEqual(manifest["status"], "captured")
                self.assertEqual(manifest["side"], side)
                self.assertEqual(manifest["candidateBuildMode"], "debug")
                self.assertTrue((output / side / "trace.jsonl").is_file())

    def test_failed_assertion_preserves_trace_and_journal_without_fidelity_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            container = root / "container"
            (container / "Documents").mkdir(parents=True)
            (container / "Documents/rec-lab.jsonl").write_text('{"k":"lab_start"}\n')
            udid = str(uuid.uuid4())
            output = root / "capture"
            calls = []

            def command(args, **kwargs):
                args = [str(arg) for arg in args]
                calls.append(args)
                if args[:4] == ["xcrun", "simctl", "list", "devices"]:
                    return json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0":
                                                   [{"udid": udid, "state": "Booted"}]}})
                if "test-without-building" in args:
                    raise LabError("root-footer assertion failed")
                if "get_app_container" in args:
                    return str(container)
                if "attachments" in args:
                    shots = Path(args[args.index("--output-path") + 1])
                    shots.mkdir()
                    (shots / "events.json").write_text(json.dumps([
                        {"k": "lab_environment", "rm": False, "rt": False},
                        {"k": "lab_assert", "id": "footer", "expected": True, "actual": False}]))
                return ""

            with patch.object(simulator, "command", side_effect=command), patch.object(simulator, "provenance", return_value={"schema": 1}):
                with self.assertRaisesRegex(LabError, "assertion failed"):
                    simulator.capture_native({"id": "test", "appearance": "light"}, output, udid)
            metadata = json.loads((output / "manifest.json").read_text())
            self.assertEqual(metadata["status"], "failed")
            self.assertEqual(metadata["coverageEnvironment"]["nativeTarget"], "simulator")
            self.assertIn('"actual": false', (output / "trace.jsonl").read_text())
            self.assertTrue((output / "runner-events.json").is_file())
            self.assertFalse((Path("/tmp/morph-native") / f"simulator-{udid}.lock").exists())
            self.assertTrue(all("devicectl" not in call for call in calls))
            self.assertIn("NO", next(call for call in calls if "test-without-building" in call))

    def test_unknown_simulator_is_rejected_before_writing_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "capture"
            with patch.object(simulator, "command", return_value='{"devices":{}}'):
                with self.assertRaisesRegex(LabError, "available simulator"):
                    simulator.capture_native({"id": "test"}, output, "unknown")
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
