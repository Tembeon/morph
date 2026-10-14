"""Capture native and Flutter telemetry with one XCUITest scenario runner.

Simulator observations are a separate target and never substitute for physical
device optics, haptics, frame scheduling or energy measurements. This first
adapter captures telemetry and screenshot attachments; optical films are pending.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import sys

from .capture import PROBE, ROOT, command, device_lock, provenance
from .scenario import LabError, digest, validate


def capture_native(scenario, out, simulator, native_scene="lab"):
    return capture_simulator(scenario, out, simulator, native_scene=native_scene)


def collect_side(output, simulator, side, metadata, xcode, env):
    output.mkdir(parents=True, exist_ok=True)
    manifest = output / "manifest.json"
    metadata = {**metadata, "side": side, "status": "running"}
    manifest.write_text(json.dumps(metadata, indent=2))
    try:
        test_error = None
        try:
            command(xcode + ["test-without-building", "-only-testing:ProbeUITests/LabUITests/testScenario",
                             "-resultBundlePath", str(output / "test.xcresult")],
                    env={**env, "TEST_RUNNER_PROBE_LAB_SIDE": side}, log=output / "test.log")
        except LabError as error:
            test_error = error
        bundle, trace = (("dev.tembeon.morph.probe", "Documents/rec-lab.jsonl") if side == "native"
                         else ("dev.tembeon.morphExample", "tmp/morph-lab.jsonl"))
        container = Path(command(["xcrun", "simctl", "get_app_container", simulator, bundle, "data"]).strip())
        source = container / trace
        if not source.is_file():
            raise LabError(f"{side} trace missing after test")
        shutil.copyfile(source, output / "trace.jsonl")
        command(["xcrun", "xcresulttool", "export", "attachments", "--path", output / "test.xcresult",
                 "--output-path", output / "shots"])
        events = []
        for attachment in (output / "shots").rglob("*"):
            if not attachment.is_file():
                continue
            try:
                rows = json.loads(attachment.read_text())
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if isinstance(rows, list) and rows and isinstance(rows[0], dict) and rows[0].get("k") == "lab_environment":
                events.extend(rows)
        if not events:
            if test_error:
                raise test_error
            raise LabError("runner settings/step journal missing")
        (output / "runner-events.json").write_text(json.dumps(events, indent=2))
        with (output / "trace.jsonl").open("a") as handle:
            for row in events:
                if row.get("k") in ("lab_environment", "lab_assert"):
                    handle.write(json.dumps(row) + "\n")
        if test_error:
            raise test_error
        metadata["status"] = "captured"
    except BaseException:
        metadata["status"] = "failed"
        raise
    finally:
        manifest.write_text(json.dumps(metadata, indent=2))


def capture_simulator(scenario, out, simulator, side="native", native_scene="lab", flutter="flutter", target="lib/lab/main.dart"):
    if side not in ("native", "flutter", "both"):
        raise LabError("side must be native, flutter or both")
    listing = json.loads(command(["xcrun", "simctl", "list", "devices", "available", "--json"]))
    matches = [(runtime, device) for runtime, devices in listing["devices"].items() for device in devices if device["udid"] == simulator]
    if len(matches) != 1:
        raise LabError("specify one available simulator UDID")
    runtime, device = matches[0]
    if "iOS-" not in runtime:
        raise LabError("target must be an iOS simulator")
    output = Path(out).resolve()
    # Atomic lock per simulator; never touch a phone lock or another owner's lock.
    lock = Path("/tmp/morph-native") / f"simulator-{simulator}.lock"
    with device_lock(f"morph-lab simulator: {scenario['id']}", path=lock):
        output.mkdir(parents=True, exist_ok=False)
        metadata = provenance(scenario)
        metadata.update({"device": simulator, "simulator": device, "runtime": runtime,
                         "side": side, "status": "building", "film": False,
                         "coverageEnvironment": {"nativeOSMajor": int(runtime.split("iOS-")[1].split("-")[0]),
                                                 "nativeTarget": "simulator", "appearance": scenario["appearance"]},
                         "limitations": ["No optical film, haptics or physical device performance proof",
                                         "Flutter simulator uses debug; timing is not release performance evidence"]})
        (output / "scenario.json").write_text(json.dumps(scenario, indent=2))
        manifest = output / "manifest.json"
        manifest.write_text(json.dumps(metadata, indent=2))
        encoded = json.dumps(scenario, sort_keys=True, separators=(",", ":"))
        env = {**os.environ, "PROBE_TEAM": "", "TEST_RUNNER_PROBE_LAB_JSON": encoded,
               "TEST_RUNNER_PROBE_LAB_SCENE": native_scene}
        derived = output / "derived"
        xcode = ["xcodebuild", "-project", str(PROBE / "Probe.xcodeproj"), "-scheme", "Probe",
                 "-configuration", "Release", "-destination", f"platform=iOS Simulator,id={simulator}",
                 "-derivedDataPath", str(derived), "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO"]
        try:
            if device["state"] != "Booted":
                command(["xcrun", "simctl", "boot", simulator])
            command(["xcrun", "simctl", "bootstatus", simulator, "-b"], timeout=180)
            command(["xcodegen", "generate", "--spec", "project.yml", "--quiet"], cwd=PROBE, env=env)
            command(xcode + ["build-for-testing"], env=env, log=output / "build.log")
            if side in ("flutter", "both"):
                metadata["flutter"] = command([flutter, "--version"], cwd=ROOT).strip()
                metadata["candidateBuildMode"] = "debug"
                payload = base64.b64encode(encoded.encode()).decode()
                command([flutter, "build", "ios", "--simulator", "--debug", "--no-pub", "--target", target,
                         f"--dart-define=MORPH_LAB_SCENARIO={payload}", f"--dart-define=MORPH_LAB_SHA256={digest(scenario)}"],
                        cwd=ROOT / "example", log=output / "flutter-build.log")
                command(["xcrun", "simctl", "install", simulator, ROOT / "example/build/ios/iphonesimulator/Runner.app"])
            for current in (("native", "flutter") if side == "both" else (side,)):
                destination = output / current if side == "both" else output
                collect_side(destination, simulator, current, metadata, xcode, env)
            metadata["status"] = "captured"
        except BaseException:
            metadata["status"] = "failed"
            raise
        finally:
            manifest.write_text(json.dumps(metadata, indent=2))
        print(f"OBSERVED {side} simulator: {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenario", type=Path)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--native-scene", default="lab")
    parser.add_argument("--side", choices=("native", "flutter", "both"), default="native")
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--target", default="lib/lab/main.dart")
    args = parser.parse_args()
    try:
        scenario = json.loads(args.scenario.read_text())
        validate(scenario)
        capture_simulator(scenario, args.out, args.simulator, args.side, args.native_scene, args.flutter, args.target)
    except (LabError, OSError, ValueError) as error:
        parser.exit(1, f"ERROR: {error}\n")


if __name__ == "__main__":
    main()
