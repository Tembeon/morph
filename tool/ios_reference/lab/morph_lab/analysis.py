import bisect
import json
import math
from collections import defaultdict
from pathlib import Path

import numpy as np

from .scenario import LabError, digest


def read_rows(path):
    rows = []
    for index, line in enumerate(Path(path).read_text().splitlines()):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise LabError(f"{path}:{index + 1}: {error}") from error
        if not isinstance(row, dict):
            raise LabError(f"{path}:{index + 1}: expected object")
        if "t" in row and (not isinstance(row["t"], (int, float)) or not math.isfinite(row["t"])):
            raise LabError(f"{path}:{index + 1}: invalid time")
        rows.append(row)
    return rows


def origin(rows):
    touches = [r.get("delivered_t", r["t"]) for r in rows if r.get("k") == "touch" and r.get("phase") == 0]
    if touches:
        return min(touches)
    starts = [r["t"] for r in rows if r.get("k") in ("lab_start", "start")]
    if not starts:
        raise LabError("trace has neither touches nor a start row")
    return min(starts)


def percentile(values, p):
    return float(np.percentile(values, p)) if values else None


def statistics(values):
    if not values:
        return {"count": 0, "rms": None, "max": None, "p95": None}
    array = np.asarray(values, dtype=float)
    return {"count": len(values), "rms": float(np.sqrt(np.mean(array * array))), "max": float(np.max(np.abs(array))), "p95": float(np.percentile(np.abs(array), 95))}


def strokes(rows):
    active = {}
    output = []
    for row in rows:
        if row.get("k") != "touch":
            continue
        pointer = str(row.get("pointer", "0"))
        phase = row.get("phase")
        if phase == 0:
            stroke = {"points": [row], "complete": False, "cancelled": False}
            active[pointer] = stroke
            output.append(stroke)
        elif pointer in active:
            active[pointer]["points"].append(row)
            if phase in (3, 4):
                active[pointer]["complete"] = True
                active[pointer]["cancelled"] = phase == 4
                del active[pointer]
    return output


def compare_input(native, candidate):
    a, b = strokes(native), strokes(candidate)
    output = []
    duration_errors, start_errors, path_errors = [], [], []
    oa = min((r["t"] for r in native if r.get("k") == "touch" and r.get("phase") == 0), default=origin(native))
    ob = min((r["t"] for r in candidate if r.get("k") == "touch" and r.get("phase") == 0), default=origin(candidate))
    for index, (left, right) in enumerate(zip(a, b)):
        la, lb = left["points"], right["points"]
        ta = np.array([r["t"] - la[0]["t"] for r in la])
        tb = np.array([r["t"] - lb[0]["t"] for r in lb])
        duration_errors.append((tb[-1] - ta[-1]) * 1000)
        start_errors.append(((lb[0]["t"] - ob) - (la[0]["t"] - oa)) * 1000)
        common = min(ta[-1], tb[-1])
        times = np.linspace(0, common, max(2, int(common * 120) + 1))
        xa = np.interp(times, ta, [r["x"] for r in la])
        ya = np.interp(times, ta, [r["y"] for r in la])
        xb = np.interp(times, tb, [r["x"] for r in lb])
        yb = np.interp(times, tb, [r["y"] for r in lb])
        errors = np.hypot(xb - xa, yb - ya).tolist()
        path_errors.extend(errors)
        output.append({"index": index, "nativeDurationMs": float(ta[-1] * 1000), "candidateDurationMs": float(tb[-1] * 1000),
                       "startDriftMs": start_errors[-1], "path": statistics(errors),
                       "nativeCancelled": left["cancelled"], "candidateCancelled": right["cancelled"],
                       "nativeComplete": left["complete"], "candidateComplete": right["complete"],
                       "native": [{"t": r["t"] - oa, "x": r["x"], "y": r["y"], "phase": r["phase"]} for r in la],
                       "candidate": [{"t": r["t"] - ob, "x": r["x"], "y": r["y"], "phase": r["phase"]} for r in lb]})
    return {"nativeCount": len(a), "candidateCount": len(b), "durationErrorMs": statistics(duration_errors),
            "startDriftMs": statistics(start_errors), "pathErrorPt": statistics(path_errors), "strokes": output}


def cadence(times):
    deltas = [1000 * (b - a) for a, b in zip(times, times[1:]) if b > a]
    median = percentile(deltas, 50)
    return {"count": len(times), "medianGapMs": median, "p95GapMs": percentile(deltas, 95),
            "maxGapMs": max(deltas, default=None), "achievedHz": 1000 / median if median else None,
            "gapsOverTwoPeriods": sum(d > median * 2.05 for d in deltas) if median else 0}


def capture_quality(rows, scenario):
    starts = [r for r in rows if r.get("k") == "lab_start"]
    start = dict(starts[0]) if starts else {}
    environments = [r for r in rows if r.get("k") == "lab_environment"]
    if start.get("rt") is None and environments:
        start["rt"] = environments[0].get("rt")
        start["rtSource"] = "XCUITest runner UIAccessibility"
    errors = [r for r in rows if r.get("k") == "lab_error"]
    assertions = [r for r in rows if r.get("k") == "lab_assert"]
    expected_assertions = [step for step in scenario["steps"] if step["action"] == "assert"]
    for step in expected_assertions:
        observed = [row for row in assertions if row.get("id") == step["id"]]
        if len(observed) != 1 or observed[0].get("expected") != step["exists"] or observed[0].get("actual") != step["exists"]:
            errors.append({"e": "semantic assertion missing or failed", "id": step["id"]})
    if start.get("sha256") != digest(scenario):
        errors.append({"e": "scenario digest missing or mismatched"})
    expected = scenario["canvas"]
    for key, actual in (("width", start.get("w")), ("height", start.get("h")), ("scale", start.get("scale"))):
        if actual is None or abs(actual - expected[key]) > 0.1:
            errors.append({"e": f"{key} missing or mismatched", "actual": actual, "expected": expected[key]})
    ticks = [r["t"] for r in rows if r.get("k") == "lab_tick"]
    marker = [r for r in rows if r.get("k") == "lab_marker"]
    costs = [r["cost_ms"] for r in rows if r.get("k") == "lab_tick"]
    down = [r for r in rows if r.get("k") == "touch" and r.get("phase") == 0]
    return {"metadata": start, "errors": errors, "cadence": cadence(ticks), "markerCount": len(marker),
            "semanticAssertions": assertions,
            "samplingCostMs": {"median": percentile(costs, 50), "p95": percentile(costs, 95), "max": max(costs, default=None)},
            "touchClockBasis": "delivery" if down and "delivered_t" in down[0] else "source fallback",
            "timingUncertainty": "native marker predicts targetTimestamp; Flutter marker is logged postFrame; physical presentation is not timestamped"}


def tracks(rows):
    output = defaultdict(list)
    for row in rows:
        if row.get("k") == "lab_sample":
            output[row["id"]].append(row)
    for values in output.values():
        values.sort(key=lambda r: r["t"])
    return output


def interpolate(samples, times, t, max_gap=0.05):
    index = bisect.bisect_left(times, t)
    if index < len(times) and abs(times[index] - t) < 1e-8:
        return samples[index]["values"]
    if index == 0 or index == len(times):
        return None
    a, b = samples[index - 1], samples[index]
    span = b["t"] - a["t"]
    if span <= 0 or span > max_gap:
        return None
    if a.get("identity") != b.get("identity"):
        return None
    f = (t - a["t"]) / span
    return {key: value + (b["values"][key] - value) * f for key, value in a["values"].items()
            if key in b["values"] and isinstance(value, (int, float)) and isinstance(b["values"][key], (int, float))}


def clipping(row):
    v = row["values"]
    if not all(k in v for k in ("left", "top", "width", "height")):
        return None
    if v.get("opacity", 1) <= 0.01:
        return 0
    l, t, w, h = (v[k] for k in ("left", "top", "width", "height"))
    losses = []
    for x, y, cw, ch in row.get("clips", []):
        losses.extend((max(0, x - l), max(0, y - t), max(0, l + w - x - cw), max(0, t + h - y - ch)))
    return max(losses, default=0)


def compare_geometry(native, candidate, origins=None, window=None):
    left, right = tracks(native), tracks(candidate)
    oa, ob = origins or (origin(native), origin(candidate))
    output = {}
    all_errors = []
    max_step = None
    max_clip = None
    for name in sorted(set(left) | set(right)):
        a, b = left.get(name, []), right.get(name, [])
        if window:
            a = [r for r in a if window[0] <= r["t"] - oa <= window[1]]
            b = [r for r in b if window[0] <= r["t"] - ob <= window[1]]
        bt = [r["t"] for r in b]
        errors = defaultdict(list)
        paired = []
        for row in a:
            t = row["t"] - oa
            value = interpolate(b, bt, t + ob)
            if value is None:
                continue
            shared = {k for k, v in row["values"].items() if isinstance(v, (int, float)) and k in value}
            if not shared:
                continue
            record = {"t": t, "native": row["values"], "candidate": value}
            paired.append(record)
            for key, av in row["values"].items():
                if key in value and isinstance(av, (int, float)):
                    error = value[key] - av
                    errors[key].append(error)
                    if key in ("left", "top", "width", "height"):
                        all_errors.append(error)
        steps = [abs(y["values"]["left"] - x["values"]["left"]) for x, y in zip(b, b[1:])
                 if "left" in x["values"] and "left" in y["values"] and x.get("identity") == y.get("identity")
                 and 0 < y["t"] - x["t"] <= 0.05 and x["values"].get("opacity", 1) > 0.01 and y["values"].get("opacity", 1) > 0.01]
        clip = [loss for r in b if (loss := clipping(r)) is not None]
        identities = [r.get("identity") for r in b]
        if steps:
            max_step = max(max_step or 0, max(steps))
        if clip:
            max_clip = max(max_clip or 0, max(clip))
        motion = {}
        for side, samples in (("native", a), ("candidate", b)):
            motion[side] = {}
            for key in ("left", "top", "width", "height", "scrollY"):
                velocities = [(y["values"][key] - x["values"][key]) / (y["t"] - x["t"]) for x, y in zip(samples, samples[1:])
                              if key in x["values"] and key in y["values"] and 0 < y["t"] - x["t"] <= 0.05 and x.get("identity") == y.get("identity")]
                motion[side][key] = {"velocityPtPerSecond": statistics(velocities)}
        output[name] = {"nativeCount": len(a), "candidateCount": len(b), "pairedCount": len(paired), "motion": motion,
                        "properties": {k: statistics(v) for k, v in errors.items()},
                        "maxHorizontalStepPt": max(steps, default=None), "maxClipLossPt": max(clip, default=None),
                        "identityChanges": sum(x != y for x, y in zip(identities, identities[1:])), "paired": paired,
                        "native": [{"t": r["t"] - oa, "values": r["values"]} for r in a],
                        "candidate": [{"t": r["t"] - ob, "values": r["values"]} for r in b]}
    return {"boundsErrorPt": statistics(all_errors), "maxHorizontalStepPt": max_step, "maxClipLossPt": max_clip, "tracks": output}


def compare_windows(native, candidate, scenario):
    a, b = strokes(native), strokes(candidate)
    steps = [step["id"] for step in scenario["steps"] if step["action"] == "gesture"
             for _ in step.get("paths", [step])]
    oa, ob = origin(native), origin(candidate)
    windows = []
    for index, (left, right) in enumerate(zip(a, b)):
        first_a, first_b = left["points"][0], right["points"][0]
        ta = first_a.get("delivered_t", first_a["t"])
        tb = first_b.get("delivered_t", first_b["t"])
        last_a, last_b = left["points"][-1], right["points"][-1]
        duration_a = last_a.get("delivered_t", last_a["t"]) - ta
        duration_b = last_b.get("delivered_t", last_b["t"]) - tb
        end = max(duration_a, duration_b) + 0.75
        for fingers, anchor in ((a, ta), (b, tb)):
            if index + 1 < len(fingers):
                point = fingers[index + 1]["points"][0]
                end = min(end, point.get("delivered_t", point["t"]) - anchor)
        windows.append({"stroke": index, "step": steps[index] if index < len(steps) else str(index),
                        "alignment": "received down; no fitted delay, duration stretch or time warping; inspection only",
                        "start": -0.15, "end": end, "nativeOrigin": ta, "candidateOrigin": tb,
                        "nativeGlobalOffset": ta - oa, "candidateGlobalOffset": tb - ob,
                        "startDriftMs": ((tb - ob) - (ta - oa)) * 1000,
                        "releaseDifferenceMs": (duration_b - duration_a) * 1000,
                        "geometry": compare_geometry(native, candidate, (ta, tb), (-0.15, end))})
    return windows


def response_windows(rows, threshold=0.1):
    output = []
    for index, stroke in enumerate(strokes(rows)):
        began = stroke["points"][0].get("delivered_t", stroke["points"][0]["t"])
        for name, samples in tracks(rows).items():
            baseline = [r for r in samples if began - 0.15 <= r["t"] < began]
            if not baseline:
                continue
            thresholds = {"left": threshold, "top": threshold, "width": threshold, "height": threshold, "scaleX": 0.001, "scaleY": 0.001, "opacity": 0.01}
            values = {key: float(np.median([r["values"][key] for r in baseline if key in r["values"]]))
                      for key in thresholds if any(key in r["values"] for r in baseline)}
            previous = began
            response = None
            for row in samples:
                if row["t"] < began:
                    continue
                if row["t"] > began + 0.5:
                    break
                if any(abs(row["values"].get(key, value) - value) > thresholds[key] for key, value in values.items()):
                    response = {"lowerMs": max(0, previous - began) * 1000, "upperMs": (row["t"] - began) * 1000}
                    break
                previous = row["t"]
            output.append({"stroke": index, "track": name, "thresholds": thresholds, "firstObservedResponse": response})
    return output


def compare_events(native, candidate):
    def events(rows):
        output = defaultdict(list)
        o = origin(rows)
        fingers = strokes(rows)
        for row in rows:
            if row.get("k") == "lab_event":
                preceding = [stroke for stroke in fingers if stroke["points"][0].get("delivered_t", stroke["points"][0]["t"]) <= row["t"]]
                down, up = None, None
                if preceding:
                    stroke = preceding[-1]
                    point = stroke["points"][0]
                    down = (row["t"] - point.get("delivered_t", point["t"])) * 1000
                    last = stroke["points"][-1]
                    release = last.get("delivered_t", last["t"])
                    near_release = row["e"] in ("activate", "selected") and abs(row["t"] - release) <= 0.01
                    if last["phase"] in (3, 4) and (release <= row["t"] or near_release):
                        up = (row["t"] - release) * 1000
                output[(row["id"], row["e"])].append({**row, "t": row["t"] - o, "fromDownMs": down, "fromUpMs": up})
        return output
    a, b = events(native), events(candidate)
    output = []
    latency = []
    for key in sorted(set(a) | set(b)):
        left, right = a.get(key, []), b.get(key, [])
        errors = [(y["t"] - x["t"]) * 1000 for x, y in zip(left, right)] if key[1] != "changed" else []
        latency.extend(errors)
        output.append({"id": key[0], "event": key[1], "nativeCount": len(left), "candidateCount": len(right),
                       "latencyDifferenceMs": statistics(errors), "native": left, "candidate": right})
    return {"discreteLatencyDifferenceMs": statistics(latency), "groups": output}


def compare(native, candidate, scenario):
    quality = {"native": capture_quality(native, scenario), "candidate": capture_quality(candidate, scenario)}
    inputs = compare_input(native, candidate)
    geometry = compare_geometry(native, candidate)
    events = compare_events(native, candidate)
    failures = []
    for side, q in quality.items():
        if q["errors"]:
            failures.append(f"{side}: invalid capture metadata")
        if q["cadence"]["count"] < 2:
            failures.append(f"{side}: no frame cadence")
    for key in ("rm", "rt"):
        if quality["native"]["metadata"].get(key) is None or quality["candidate"]["metadata"].get(key) is None:
            failures.append(f"accessibility setting {key} was not read back")
        if quality["native"]["metadata"].get(key) != quality["candidate"]["metadata"].get(key):
            failures.append(f"accessibility setting {key} differs")
    if quality["native"]["touchClockBasis"] != quality["candidate"]["touchClockBasis"]:
        failures.append("touch clock bases differ; source time and delivery time cannot be equated")
    if inputs["nativeCount"] != inputs["candidateCount"]:
        failures.append("received gesture counts differ")
    expected = sum(len(step.get("paths", [step])) for step in scenario["steps"] if step["action"] == "gesture")
    for side in ("native", "candidate"):
        if inputs[side + "Count"] != expected:
            failures.append(f"{side}: received gesture count does not match the scenario")
    for stroke in inputs["strokes"]:
        if not stroke["nativeComplete"] or not stroke["candidateComplete"]:
            failures.append(f"stroke {stroke['index']}: incomplete")
        if stroke["nativeCancelled"] != stroke["candidateCancelled"]:
            failures.append(f"stroke {stroke['index']}: cancellation differs")
    for track in scenario.get("tracks", []):
        matches = [v for k, v in geometry["tracks"].items() if k == track["id"] or k.startswith(track["id"] + "/")]
        if not matches or not any(v["pairedCount"] and v["properties"] for v in matches):
            failures.append(f"track {track['id']}: no comparable samples")
        for name, observed in geometry["tracks"].items():
            if name != track["id"] and not name.startswith(track["id"] + "/"):
                continue
            if not observed["nativeCount"] or not observed["candidateCount"]:
                failures.append(f"track {name}: an observed instance is missing from one source")
            for property_name in track.get("properties", []):
                if property_name not in observed["properties"]:
                    failures.append(f"track {name}: missing corresponding property {property_name}")
    for group in events["groups"]:
        if group["event"] == "changed":
            continue
        if group["nativeCount"] != group["candidateCount"]:
            failures.append(f"event {group['id']} {group['event']}: counts differ")
        if [e.get("value") for e in group["native"]] != [e.get("value") for e in group["candidate"]]:
            failures.append(f"event {group['id']} {group['event']}: values differ")
    values = {"geometryRmsPt": geometry["boundsErrorPt"]["rms"], "geometryMaxPt": geometry["boundsErrorPt"]["max"],
              "horizontalStepPt": geometry["maxHorizontalStepPt"], "touchPathRmsPt": inputs["pathErrorPt"]["rms"],
              "clipLossPt": geometry["maxClipLossPt"],
              "eventLatencyMs": events["discreteLatencyDifferenceMs"]["max"],
              "frameGapMs": max((q["cadence"]["maxGapMs"] or 0 for q in quality.values()), default=None)}
    for name, limit in scenario.get("gates", {}).items():
        actual = values[name]
        if actual is None or actual > limit:
            failures.append(f"{name}: {actual} exceeds {limit}")
    return {"schema": 1, "scenario": scenario["id"], "alignment": "geometry: first delivered touch; input paths: first source touch; one offset, no time warping",
            "quality": quality, "input": inputs, "geometry": geometry, "events": events,
            "responseWindows": {"native": response_windows(native), "candidate": response_windows(candidate)},
            "fidelityGatesDeclared": bool(scenario.get("gates") or any(r.get("gates") for r in scenario.get("regions", []))),
            "failures": failures, "passed": not failures}
