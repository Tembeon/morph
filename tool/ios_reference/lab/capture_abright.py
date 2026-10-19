"""Device capture of the adaptive bar brightness scene "abright".

Runs AdaptiveBrightnessUITests on the iPhone under the device lock, one xcodebuild test run per
pass, films the passes that need a film with the headless MorphRecorder, exports the screenshot
attachments and pulls the probe's rows. The owner sets the system appearance before a run
(Settings > Display); the probe never forces it. See spec/adaptive-brightness-capture.md.

    cd tool/ios_reference/lab
    python3 capture_abright.py --theme light            # every default pass, about 25 min
    python3 capture_abright.py --theme dark             # stairs, steps, scroll, about 16 min
    python3 capture_abright.py --theme light --passes pocketflag
    python3 capture_abright.py --build-only             # compile check, no device, no lock

Then: python3 analyze_abright.py <out>
"""
import argparse
import contextlib
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from morph_lab.capture import LabError, device_lock

ROOT = Path(__file__).resolve().parents[3]
PROBE = ROOT / "tool/ios_reference"

# name: (test method, filmed, estimated seconds of phone time without xcodebuild overhead)
PASSES = {
    "stairs": ("testABStairs", False, 400),
    "toolbar": ("testABToolbarStairs", False, 171),
    "steps": ("testABSteps", True, 232),
    "colours": ("testABColours", False, 76),
    "coverage": ("testABCoverage", False, 56),
    "scroll": ("testABScroll", True, 229),
    "search": ("testABSearch", True, 52),
    "pocketflag": ("testABPocketFlag", True, 116),
}
DEFAULT = {
    "light": ["stairs", "toolbar", "steps", "colours", "coverage", "scroll", "search"],
    "dark": ["stairs", "steps", "scroll"],
}
OVERHEAD = 45


@contextlib.contextmanager
def film(folder, record):
    stop = folder / "recorder.stop"
    log = folder / "recorder.log"
    log.touch()
    binary = PROBE / "screen_recorder/build/MorphRecorder.app/Contents/MacOS/MorphRecorder"
    arguments = ["nice", "-n", "10", str(binary), str(log), str(folder / "movie.mov"), "1800", str(folder / "capture-buffers.jsonl"), str(stop)]
    with (folder / "recorder-process.log").open("w") as output:
        process = subprocess.Popen(arguments, stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 40
            while "recording " not in log.read_text():
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise LabError(f"recorder did not start; see {log}")
                time.sleep(0.25)
            yield
        finally:
            stop.touch()
            try:
                status = process.wait(timeout=60)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait()
                status = 124
            record("recorder", arguments, status)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--theme", choices=["light", "dark"], help="the system appearance the owner set; names the records")
    parser.add_argument("--passes", help="comma list of " + ", ".join(PASSES) + " (default by theme)")
    parser.add_argument("--only", default="", help="capture names inside the passes (PROBE_ONLY)")
    parser.add_argument("--fine", default="", help="centres of the fine staircases, '<falling>,<rising>' (default by theme)")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--no-film", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--device", default="00008140-001039D01442801C")
    parser.add_argument("--team", default="83S63575XD")
    args = parser.parse_args()
    if not args.build_only and not args.theme:
        parser.error("--theme is required for a device run")
    passes = [p for p in (args.passes.split(",") if args.passes else DEFAULT.get(args.theme, [])) if p]
    unknown = [p for p in passes if p not in PASSES]
    if unknown:
        parser.error(f"unknown passes: {unknown}")
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M")
    out = (args.out or PROBE / f"recordings/abright-{args.theme or 'build'}-{stamp}").resolve()
    out.mkdir(parents=True, exist_ok=True)
    receipt = {"theme": args.theme, "passes": passes, "device": args.device, "commands": []}

    def record(name, arguments, status):
        receipt["commands"].append({"name": name, "argv": [str(a) for a in arguments], "exitCode": status})
        (out / "commands.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(f"{name}: exit {status}", flush=True)

    env = dict(os.environ, PROBE_TEAM=args.team, TEST_RUNNER_PROBE_AB_TAG=args.theme or "sys",
               TEST_RUNNER_PROBE_ONLY=args.only, TEST_RUNNER_PROBE_AB_FINE=args.fine)

    def run(arguments, name, log, timeout=600):
        with log.open("w") as handle:
            try:
                status = subprocess.run([str(a) for a in arguments], cwd=PROBE, env=env, stdout=handle, stderr=subprocess.STDOUT, timeout=timeout).returncode
            except subprocess.TimeoutExpired:
                status = 124
        record(name, arguments, status)
        return status

    estimate = sum(PASSES[p][2] + OVERHEAD for p in passes)
    print(f"passes {passes}, about {estimate / 60:.0f} min; output {out}", flush=True)
    common = ["nice", "-n", "10", "xcodebuild", "-project", "Probe.xcodeproj", "-scheme", "Probe", "-configuration", "Release",
              "-derivedDataPath", "build/device-derived", "-allowProvisioningUpdates", f"DEVELOPMENT_TEAM={args.team}"]
    lock = contextlib.nullcontext() if args.build_only else device_lock(f"abright {args.theme} {out.name}")
    with lock:
        if run(["/opt/homebrew/bin/xcodegen", "generate", "--spec", "project.yml", "--quiet"], "generate", out / "generate.log"):
            return 1
        if not args.skip_build:
            destination = "generic/platform=iOS" if args.build_only else f"id={args.device}"
            if run(common + ["-destination", destination, "build-for-testing"], "build", out / "build.log", timeout=1200):
                print((out / "build.log").read_text()[-4000:])
                return 1
        if args.build_only:
            return 0
        needs_film = not args.no_film and any(PASSES[p][1] for p in passes)
        recorder = PROBE / "screen_recorder/build/MorphRecorder.app/Contents/MacOS/MorphRecorder"
        if needs_film and not recorder.exists():
            if run(["sh", "screen_recorder/build.sh"], "recorder-build", out / "recorder-build.log"):
                return 1
        failed = []
        for name in passes:
            test, filmed, seconds = PASSES[name]
            folder = out / name
            folder.mkdir(exist_ok=True)
            result = folder / "result.xcresult"
            if result.exists():
                subprocess.run(["rm", "-rf", str(result)])
            print(f"pass {name}: {test}, about {seconds / 60:.1f} min{' (filmed)' if filmed and not args.no_film else ''}", flush=True)
            arguments = common + ["-destination", f"id={args.device}", "test-without-building", "-parallel-testing-enabled", "NO",
                                  f"-only-testing:ProbeUITests/AdaptiveBrightnessUITests/{test}", "-resultBundlePath", str(result)]
            recording = film(folder, record) if filmed and not args.no_film else contextlib.nullcontext()
            with recording:
                status = run(arguments, f"test-{name}", folder / "test.log", timeout=seconds * 3 + 600)
            if status:
                failed.append(name)
            if result.exists():
                run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result), "--output-path", str(folder / "attachments")],
                    f"export-{name}", folder / "export.log")
        run(["xcrun", "devicectl", "device", "copy", "from", "--device", args.device, "--domain-type", "appDataContainer",
             "--domain-identifier", "dev.tembeon.morph.probe", "--source", "Documents", "--destination", str(out / "rows")],
            "pull", out / "pull.log")
    print(f"done: {out}" + (f"; failed passes {failed}" if failed else ""), flush=True)
    print(f"analyse: python3 analyze_abright.py {out}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except LabError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
