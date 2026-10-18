import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from morph_lab.capture import device_lock

ROOT = Path(__file__).resolve().parents[3]
PROBE = ROOT / "tool/ios_reference"
TESTS = {"placement": "testKeyboardPlacement", "selection": "testKeyboardSelectionReopen"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--test", choices=TESTS, default="selection")
    parser.add_argument("--rows", type=int, choices=[3, 10], default=10)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--device", default="00008140-001039D01442801C")
    parser.add_argument("--team", default="83S63575XD")
    args = parser.parse_args()
    out = args.out.resolve()
    if re.fullmatch(r"[a-z0-9-]+", out.name) is None:
        parser.error("output name must contain lowercase letters, digits, or hyphens")
    if args.skip_build and args.build_only:
        parser.error("--skip-build and --build-only are mutually exclusive")
    raw = Path.home() / "morph-re/measurements/menu-keyboard" / out.name
    if raw.exists() or out.exists():
        parser.error("capture output already exists")
    raw.mkdir(parents=True)
    out.mkdir(parents=True)
    sources = [p for folder in [PROBE / "Sources", PROBE / "UITests"] for p in sorted(folder.glob("*.swift"))]
    source_hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    state = PROBE / "build/device-derived/menu-keyboard-source-hashes.json"
    receipt = {"test": args.test, "rows": args.rows, "sourceSha256": source_hashes, "commands": []}

    def run(arguments, name):
        with (raw / f"{name}.log").open("w") as log:
            try:
                result = subprocess.run(arguments, cwd=PROBE, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=240)
                status = result.returncode
            except subprocess.TimeoutExpired:
                status = 124
        receipt["commands"].append({"name": name, "argv": [str(x) for x in arguments], "exitCode": status})
        (out / "commands.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(f"{name}: exit {status}", flush=True)
        return status

    env = dict(os.environ, PROBE_TEAM=args.team, TEST_RUNNER_PROBE_KEYBOARD_ROWS=str(args.rows))
    lock = contextlib.nullcontext() if args.build_only else device_lock(f"menu-keyboard {out.name}")
    with lock:
        if run(["/opt/homebrew/bin/xcodegen", "generate", "--spec", "project.yml", "--quiet"], "generate"):
            return 1
        common = ["nice", "-n", "10", "xcodebuild", "-project", "Probe.xcodeproj", "-scheme", "Probe", "-configuration", "Release",
                  "-destination", "generic/platform=iOS" if args.build_only else f"id={args.device}", "-derivedDataPath", "build/device-derived",
                  "-allowProvisioningUpdates", f"DEVELOPMENT_TEAM={args.team}"]
        if args.skip_build:
            if not state.exists() or json.loads(state.read_text()) != source_hashes:
                parser.error("native sources differ from the saved build; omit --skip-build")
        else:
            if run(common + ["build-for-testing"], "build"):
                return 1
            state.write_text(json.dumps(source_hashes, indent=2) + "\n")
        if args.build_only:
            return 0
        result = raw / "result.xcresult"
        status = run(common + ["test-without-building", "-parallel-testing-enabled", "NO", f"-only-testing:ProbeUITests/MenuKeyboardUITests/{TESTS[args.test]}",
                               "-resultBundlePath", str(result)], "test")
        artifact_status = run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result), "--output-path", str(raw / "attachments")], "export")
        if status:
            return status
        for mode in ["none", "show", "hide"]:
            artifact_status += run(["xcrun", "devicectl", "device", "copy", "from", "--device", args.device, "--domain-type", "appDataContainer",
                                    "--domain-identifier", "dev.tembeon.morph.probe", "--source", f"Documents/menu-keyboard-{mode}.json",
                                    "--destination", str(out / f"events-{mode}.json")], f"copy-{mode}")
        return status or (1 if artifact_status else 0)


if __name__ == "__main__":
    sys.exit(main())
