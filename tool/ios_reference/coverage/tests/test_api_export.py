"""Exercise the real Dart resolver, rather than a mock of its JSON output."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
import coverage as ledger


@unittest.skipUnless(shutil.which("dart"), "Dart SDK required for semantic export integration")
class ApiExportTests(unittest.TestCase):
    def test_resolved_show_exports_defaults_and_body_only_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary)
            lib = package / "lib"
            lib.mkdir()
            (package / "pubspec.yaml").write_text("name: fixture\nenvironment:\n  sdk: ^3.12.2\n")
            (lib / "foundation.dart").write_text("export 'controls.dart' show Example, Choice;\n")
            for entry in ("widgets.dart", "motion.dart", "glass_painter.dart"):
                (lib / entry).write_text("export 'foundation.dart';\n")

            def export(default, body):
                (lib / "controls.dart").write_text(
                    "class Example { const Example({this.enabled = " + default + ", this._privateField = 0}); "
                    "final bool enabled; final int _privateField; void act() { " + body + " } }\n"
                    "class Hidden {}\nenum Choice { one, two }\n")
                result = subprocess.run(["dart", "run", str(HERE / "export_api.dart"), str(package)],
                                        cwd=ROOT, capture_output=True, text=True, timeout=120)
                self.assertEqual(result.returncode, 0, result.stderr)
                return json.loads(result.stdout)

            baseline = export("false", "")
            self.assertEqual(set(baseline["symbols"]), {"CLASS:Example", "ENUM:Choice"})
            constructors = [row for row in baseline["symbols"]["CLASS:Example"]["members"] if row["kind"] == "CONSTRUCTOR"]
            self.assertEqual(constructors[0]["parameters"][0]["default"], "false")
            self.assertEqual(constructors[0]["parameters"][1]["name"], "privateField")
            body_only = export("false", "final ignored = 1; print(ignored);")
            self.assertFalse(any(ledger.api_drift(baseline, body_only).values()))
            changed = export("true", "")
            self.assertEqual(ledger.api_drift(baseline, changed)["changed"], ["CLASS:Example"])


if __name__ == "__main__":
    unittest.main()
