import argparse
import contextlib
import json
import re
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
PROBE = ROOT / "tool/ios_reference"
AUDIT = Path(__file__).resolve().parent
sys.path.insert(0, str(PROBE / "lab"))
from morph_lab.capture import device_lock

parser = argparse.ArgumentParser()
parser.add_argument("run", help="New append-only run name")
parser.add_argument("--build-only", action="store_true")
parser.add_argument("--rows", type=int, choices=[3, 10], default=10)
args = parser.parse_args()
if re.fullmatch(r"[a-z0-9-]+", args.run) is None:
    parser.error("run name must contain lowercase letters, digits, or hyphens")
raw = Path.home() / "morph-re/measurements/native-ime-20261018" / args.run
raw.mkdir(parents=True, exist_ok=False)
output = AUDIT / args.run
output.mkdir(exist_ok=False)
device = "00008140-001039D01442801C"
team = "83S63575XD"
commands = []


def run(arguments, name, cwd=PROBE, env=None):
    with (raw / f"{name}.log").open("w") as log:
        result = subprocess.run(arguments, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=360)
    commands.append({"name": name, "argv": arguments, "exitCode": result.returncode})
    (AUDIT / f"{args.run}-commands.json").write_text(json.dumps(commands, indent=2) + "\n")
    print(f"{name}: exit {result.returncode}", flush=True)
    return result.returncode


lock = contextlib.nullcontext() if args.build_only else device_lock(f"morph native-ime {args.run}")
with lock:
    env = dict(os.environ, PROBE_TEAM=team, TEST_RUNNER_PROBE_KEYBOARD_ROWS=str(args.rows))
    if run(["/opt/homebrew/bin/xcodegen", "generate", "--spec", "project.yml", "--quiet"], "generate", env=env):
        sys.exit(1)
    common = ["nice", "-n", "10", "xcodebuild", "-project", "Probe.xcodeproj", "-scheme", "Probe", "-configuration", "Release",
              "-destination", "generic/platform=iOS" if args.build_only else f"id={device}", "-derivedDataPath", "build/device-derived", "-allowProvisioningUpdates", f"DEVELOPMENT_TEAM={team}"]
    if run(common + ["build-for-testing"], "build", env=env):
        sys.exit(1)
    if args.build_only:
        sys.exit(0)
    result = raw / "result.xcresult"
    test_status = run(common + ["test-without-building", "-parallel-testing-enabled", "NO", "-only-testing:ProbeUITests/MenuKeyboardUITests/testKeyboardPlacement",
                                "-resultBundlePath", str(result)], "test", env=env)
    artifact_failures = run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result), "--output-path", str(raw / "attachments")], "export")
    for mode in ["none", "show", "hide"]:
        artifact_failures += run(["xcrun", "devicectl", "device", "copy", "from", "--device", device, "--domain-type", "appDataContainer", "--domain-identifier", "dev.tembeon.morph.probe",
             "--source", f"Documents/menu-keyboard-{mode}.json", "--destination", str(output / f"events-{mode}.json")], f"copy-{mode}")
    sys.exit(test_status or (1 if artifact_failures else 0))
