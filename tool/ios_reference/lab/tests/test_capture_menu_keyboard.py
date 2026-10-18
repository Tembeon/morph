import contextlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import capture_menu_keyboard as capture


class FailedCaptureTests(unittest.TestCase):
    def test_failed_test_never_copies_old_app_documents(self):
        for failure, expected in [(65, 65), (subprocess.TimeoutExpired("xcodebuild", 240), 124)]:
            with self.subTest(failure=expected), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                probe = root / "probe"
                (probe / "build/device-derived").mkdir(parents=True)
                (probe / "Sources").mkdir()
                (probe / "Sources/Scene.swift").write_text("import UIKit\n")
                out = root / "attempt"
                calls = []
                released = []

                @contextlib.contextmanager
                def lock(owner):
                    try:
                        yield
                    finally:
                        released.append(owner)

                def run(arguments, **kwargs):
                    calls.append(arguments)
                    if "test-without-building" in arguments:
                        if isinstance(failure, Exception):
                            raise failure
                        return subprocess.CompletedProcess(arguments, failure)
                    return subprocess.CompletedProcess(arguments, 0)

                with patch.object(capture, "ROOT", root), patch.object(capture, "PROBE", probe), patch.object(capture.Path, "home", return_value=root), patch.object(capture, "device_lock", lock), patch.object(capture.subprocess, "run", side_effect=run), patch("sys.argv", ["capture", "--out", str(out)]):
                    self.assertEqual(capture.main(), expected)
                receipt = json.loads((out / "commands.json").read_text())
                self.assertEqual([item["name"] for item in receipt["commands"]], ["generate", "build", "test", "export"])
                self.assertEqual(receipt["commands"][2]["exitCode"], expected)
                self.assertFalse(any("devicectl" in arguments for arguments in calls))
                self.assertEqual(list(out.glob("events-*.json")), [])
                self.assertEqual(len(released), 1)


class FilmLifecycleTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.raw = Path(temporary.name)
        self.process = Mock()
        self.process.poll.return_value = None
        self.process.wait.return_value = 0
        self.commands = []

    def start(self, arguments, **kwargs):
        (self.raw / "recorder.log").write_text("recording 240 s\n")
        return self.process

    def record(self, name, arguments, status):
        self.commands.append((name, status))

    def test_body_failure_stops_owned_recorder_and_preserves_error(self):
        with patch.object(capture.subprocess, "Popen", side_effect=self.start):
            with self.assertRaisesRegex(ValueError, "test execution failed"):
                with capture.record_film(self.raw, self.record):
                    raise ValueError("test execution failed")
        self.assertTrue((self.raw / "recorder.stop").is_file())
        self.process.wait.assert_called_once_with(timeout=45)
        self.process.terminate.assert_not_called()
        self.assertEqual(self.commands, [("recorder", 0)])

    def test_start_failure_never_executes_test_body(self):
        self.process.poll.return_value = 1
        self.process.wait.return_value = 1
        entered = False
        with patch.object(capture.subprocess, "Popen", return_value=self.process):
            with self.assertRaisesRegex(RuntimeError, "did not start"):
                with capture.record_film(self.raw, self.record):
                    entered = True
        self.assertFalse(entered)
        self.assertTrue((self.raw / "recorder.stop").is_file())
        self.assertEqual(self.commands, [("recorder", 1)])

    def test_shutdown_timeout_is_failed_even_if_forced_stop_succeeds(self):
        for kill in [False, True]:
            with self.subTest(kill=kill):
                self.commands.clear()
                self.process.reset_mock()
                timeouts = [subprocess.TimeoutExpired("recorder", 45)]
                if kill:
                    timeouts.append(subprocess.TimeoutExpired("recorder", 5))
                self.process.wait.side_effect = timeouts + [0]
                with patch.object(capture.subprocess, "Popen", side_effect=self.start):
                    with self.assertRaisesRegex(RuntimeError, "exit 124"):
                        with capture.record_film(self.raw, self.record):
                            pass
                self.process.terminate.assert_called_once_with()
                self.assertEqual(self.process.kill.call_count, int(kill))
                self.assertEqual(self.commands, [("recorder", 124)])


if __name__ == "__main__":
    unittest.main()
