"""Check telemetry acquisition within explicit stimulus-relative intervals.

This is a quality gate, never a fidelity metric. A dense trace of the wrong
object does not prove visual parity; track semantics still need contract review.
"""
import math

from .scenario import LabError, number


def validate_windows(scenario):
    windows = scenario.get("observationWindows", [])
    if not isinstance(windows, list):
        raise LabError("observationWindows must be a list")
    steps = {step["id"]: step for step in scenario.get("steps", [])}
    tracks = {track["id"]: track for track in scenario.get("tracks", [])}
    seen = set()
    for window in windows:
        if not isinstance(window, dict) or set(window) != {"id", "step", "start", "end", "maxGapMs", "tracks"}:
            raise LabError("observation window needs exactly id, step, start, end, maxGapMs and tracks")
        if not isinstance(window["id"], str) or not window["id"] or window["id"] in seen:
            raise LabError("observation window id must be unique and nonempty")
        seen.add(window["id"])
        step = steps.get(window["step"])
        if step is None or step["action"] != "gesture" or len(step.get("paths", [step])) != 1:
            raise LabError("observation window requires an unambiguous single-pointer gesture step")
        start = number(window["start"], "window.start")
        end = number(window["end"], "window.end")
        if start >= end:
            raise LabError("observation window start must be before end")
        if number(window["maxGapMs"], "window.maxGapMs") <= 0:
            raise LabError("observation window maxGapMs must be positive")
        if not isinstance(window["tracks"], list) or not window["tracks"]:
            raise LabError("observation window needs explicit tracks and properties")
        requested = set()
        for track in window["tracks"]:
            if not isinstance(track, dict) or set(track) != {"id", "properties"} or not isinstance(track["id"], str):
                raise LabError("window track needs id and properties")
            base, *instance = track["id"].split("/")
            if base not in tracks or (instance and (len(instance) != 1 or not instance[0].isdigit() or not tracks[base]["native"].get("all") or not tracks[base]["flutter"].get("all"))):
                raise LabError("window track must reference a declared selector and explicit instance")
            if track["id"] in requested:
                raise LabError("duplicate observation window track")
            requested.add(track["id"])
            properties = track["properties"]
            if not isinstance(properties, list) or not properties or any(not isinstance(p, str) or not p for p in properties) or len(set(properties)) != len(properties):
                raise LabError("window properties must be distinct nonempty strings")


def check_windows(native, candidate, scenario):
    windows = scenario.get("observationWindows", [])
    steps = [step["id"] for step in scenario["steps"] if step["action"] == "gesture" for _ in step.get("paths", [step])]
    output, failures = [], []
    for window in windows:
        observed = {"id": window["id"], "step": window["step"], "start": window["start"], "end": window["end"],
                    "maxGapMs": window["maxGapMs"], "sides": {}, "passed": True}
        index = steps.index(window["step"])
        for side, rows in (("native", native), ("candidate", candidate)):
            downs = [row for row in rows if row.get("k") == "touch" and row.get("phase") == 0]
            if index >= len(downs):
                failures.append(f"observation {window['id']} {side}: received gesture missing")
                observed["passed"] = False
                observed["sides"][side] = {"error": "received gesture missing"}
                continue
            origin = downs[index].get("delivered_t", downs[index]["t"])
            start, end = origin + window["start"], origin + window["end"]
            observations = {}
            for track in window["tracks"]:
                samples = [row for row in rows if row.get("k") == "lab_sample" and row.get("id") == track["id"] and start <= row["t"] <= end]
                properties = {}
                for name in track["properties"]:
                    valid = [row for row in samples if type(row.get("values", {}).get(name)) in (int, float) and math.isfinite(row["values"][name])]
                    times = sorted({start, end, *(row["t"] for row in valid)})
                    gap = max((b - a for a, b in zip(times, times[1:])), default=end - start) * 1000
                    complete = bool(valid) and len(valid) == len(samples) and gap <= window["maxGapMs"] + 1e-5
                    properties[name] = {"sampleCount": len(valid), "invalidCount": len(samples) - len(valid),
                                        "maxGapMs": gap, "passed": complete}
                    if not complete:
                        failures.append(f"observation {window['id']} {side} {track['id']}.{name}: {len(valid)} valid samples, gap {gap:.3f} ms")
                        observed["passed"] = False
                observations[track["id"]] = properties
            observed["sides"][side] = observations
        output.append(observed)
    return {"declared": bool(windows), "passed": bool(windows) and not failures, "windows": output, "failures": failures,
            "scope": "Acquisition completeness of declared telemetry channels; not optical presentation or fidelity proof"}
