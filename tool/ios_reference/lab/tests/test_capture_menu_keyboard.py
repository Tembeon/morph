import contextlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

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


if __name__ == "__main__":
    unittest.main()
