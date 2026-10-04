import base64
import contextlib
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

from .images import extract
from .scenario import LabError, digest, duration


ROOT = Path(__file__).resolve().parents[4]
PROBE = ROOT / "tool/ios_reference"


@contextlib.contextmanager
def device_lock(owner, path=Path("/tmp/morph-native/device.lock")):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    token = f"{owner}, {datetime.datetime.now(datetime.timezone.utc).isoformat()}, pid {os.getpid()}, {uuid.uuid4()}\n"
    try:
        path.mkdir()
    except FileExistsError as error:
        owner_file = path / "owner"
        current = owner_file.read_text() if owner_file.exists() else "owner not yet written"
        raise LabError(f"phone is locked: {current.strip()}") from error
    try:
        (path / "owner").write_text(token)
        yield
    finally:
        owner_file = path / "owner"
        if owner_file.exists() and owner_file.read_text() == token:
            owner_file.unlink()
            path.rmdir()


def command(args, cwd=None, env=None, log=None, timeout=900):
    print("RUN " + " ".join(str(a) if len(str(a)) < 180 else "<scenario payload>" for a in args), flush=True)
    if log:
        with Path(log).open("w") as handle:
            result = subprocess.run([str(a) for a in args], cwd=cwd, env=env, stdout=handle, stderr=subprocess.STDOUT, timeout=timeout)
        if result.returncode:
            print(Path(log).read_text()[-5000:], flush=True)
            raise LabError(f"command failed ({result.returncode}); see {log}")
        return ""
    result = subprocess.run([str(a) for a in args], cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise LabError(f"command failed ({result.returncode}): {result.stderr[-3000:]} {result.stdout[-3000:]}")
    return result.stdout


def provenance(scenario):
    files = {}
    for directory in (ROOT / "lib", ROOT / "example/lib", ROOT / "hook", PROBE / "Sources", PROBE / "UITests", PROBE / "lab/morph_lab", PROBE / "screen_recorder"):
        if directory.exists():
            for path in sorted(directory.rglob("*")):
                if path.suffix in (".dart", ".swift", ".glsl", ".frag", ".py", ".plist", ".vert"):
                    files[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    for path in (ROOT / "pubspec.yaml", ROOT / "example/pubspec.yaml", ROOT / "example/ios/Runner/Info.plist", ROOT / "example/ios/Runner/AppDelegate.swift"):
        files[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return {"schema": 1, "scenarioSha256": digest(scenario), "scenario": scenario,
            "createdUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "gitHead": command(["git", "rev-parse", "HEAD"], cwd=ROOT).strip(),
            "gitStatus": command(["git", "status", "--short"], cwd=ROOT).splitlines(),
            "xcode": command(["xcodebuild", "-version"]).strip(), "sourceHashes": files}


def pull(device, bundle, source, output, name):
    command(["xcrun", "devicectl", "device", "copy", "from", "--device", device, "--domain-type", "appDataContainer", "--domain-identifier", bundle,
             "--source", source, "--destination", output / "trace.jsonl"])
    if not (output / "trace.jsonl").exists():
        raise LabError(f"device pull did not contain {name}")


def capture(scenario, out, device, team, side="both", film=True, flutter="flutter", restore=True, target="lib/lab/main.dart", native_scene="lab"):
    out = Path(out).resolve()
    out.mkdir(parents=True, exist_ok=False)
    metadata = provenance(scenario)
    metadata["device"] = device
    metadata["status"] = "building"
    metadata["flutter"] = command([flutter, "--version"], cwd=ROOT).strip()
    (out / "manifest.json").write_text(json.dumps(metadata, indent=2))
    (out / "scenario.json").write_text(json.dumps(scenario, indent=2))
    encoded_json = json.dumps(scenario, sort_keys=True, separators=(",", ":"))
    sides = ("native", "flutter") if side == "both" else (side,)
    env = {**os.environ, "PROBE_TEAM": team}
    derived = PROBE / "build/lab-derived"
    xcode = ["xcodebuild", "-project", str(PROBE / "Probe.xcodeproj"), "-scheme", "Probe", "-configuration", "Release",
             "-destination", f"id={device}", "-derivedDataPath", str(derived), "-allowProvisioningUpdates", f"DEVELOPMENT_TEAM={team}"]
    gallery = ROOT / "example/build/ios/iphoneos/Runner.app"
    needs_restore = "flutter" in sides and restore
    with device_lock(f"morph-lab: {scenario['id']}"):
        try:
            command(["xcodegen", "generate", "--spec", "project.yml", "--quiet"], cwd=PROBE, env=env)
            command(xcode + ["build-for-testing"], env=env, log=out / "native-build.log")
            if "flutter" in sides:
                payload = base64.b64encode(encoded_json.encode()).decode()
                command([flutter, "build", "ios", "--profile", "--target", target, f"--dart-define=MORPH_LAB_SCENARIO={payload}",
                         f"--dart-define=MORPH_LAB_SHA256={digest(scenario)}"], cwd=ROOT / "example", log=out / "flutter-build.log")
                command(["xcrun", "devicectl", "device", "install", "app", "--device", device, gallery])
            if film:
                command(["sh", "build.sh"], cwd=PROBE / "screen_recorder", log=out / "recorder-build.log")
            for current in sides:
                destination = out / current
                destination.mkdir()
                recorder = None
                stop = destination / "recorder.stop"
                test_env = {**env, "TEST_RUNNER_PROBE_LAB_JSON": encoded_json,
                            "TEST_RUNNER_PROBE_LAB_SIDE": current, "TEST_RUNNER_PROBE_LAB_SCENE": native_scene}
                try:
                    if film:
                        log = destination / "recorder.log"
                        log.touch()
                        recorder = subprocess.Popen(["open", "-g", "-W", str(PROBE / "screen_recorder/build/MorphRecorder.app"), "--args",
                                                     str(log), str(destination / "movie.mov"), str(max(120, duration(scenario) + 90)),
                                                     str(destination / "capture-buffers.jsonl"), str(stop)])
                        deadline = time.monotonic() + 40
                        while "recording " not in log.read_text():
                            if recorder.poll() is not None or time.monotonic() > deadline:
                                raise LabError(f"recorder did not start: {log.read_text()}")
                            time.sleep(0.25)
                    command(xcode + ["test-without-building", "-only-testing:ProbeUITests/LabUITests/testScenario", "-resultBundlePath", str(destination / "test.xcresult")],
                            env=test_env, log=destination / "test.log")
                finally:
                    if recorder is not None:
                        stop.touch()
                        recorder.wait(timeout=45)
                        if recorder.returncode:
                            raise LabError(f"recorder failed; see {destination / 'recorder.log'}")
                if current == "native":
                    pull(device, "dev.tembeon.morph.probe", "Documents/rec-lab.jsonl", destination, "rec-lab.jsonl")
                else:
                    pull(device, "dev.tembeon.morphExample", "tmp/morph-lab.jsonl", destination, "morph-lab.jsonl")
                command(["xcrun", "xcresulttool", "export", "attachments", "--path", destination / "test.xcresult", "--output-path", destination / "shots"])
                for attachment in (destination / "shots").rglob("*"):
                    if not attachment.is_file():
                        continue
                    try:
                        journal = json.loads(attachment.read_text())
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        continue
                    if isinstance(journal, list) and journal and journal[0].get("k") == "lab_environment":
                        (destination / "runner-events.json").write_text(json.dumps(journal, indent=2))
                        with (destination / "trace.jsonl").open("a") as handle:
                            handle.write(json.dumps(journal[0]) + "\n")
                if film:
                    extract(destination / "movie.mov", destination / "frames")
                side_manifest = {**metadata, "side": current, "status": "captured", "trace": "trace.jsonl", "film": film}
                (destination / "manifest.json").write_text(json.dumps(side_manifest, indent=2))
            metadata["status"] = "captured"
        except BaseException:
            metadata["status"] = "failed"
            raise
        finally:
            (out / "manifest.json").write_text(json.dumps(metadata, indent=2))
            if needs_restore:
                command([flutter, "build", "ios", "--release", "--target", "lib/main.dart"], cwd=ROOT / "example", log=out / "gallery-build.log")
                command(["xcrun", "devicectl", "device", "install", "app", "--device", device, gallery])
                command(["xcrun", "devicectl", "device", "process", "launch", "--device", device, "dev.tembeon.morphExample"])
    return out
