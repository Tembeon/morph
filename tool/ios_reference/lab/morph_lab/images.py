import hashlib
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

from .analysis import cadence, origin, strokes
from .scenario import LabError


def image_metadata(image):
    return {"width": image.width, "height": image.height, "mode": image.mode,
            "iccSha256": hashlib.sha256(image.info["icc_profile"]).hexdigest() if image.info.get("icc_profile") else None,
            "gamma": image.info.get("gamma")}


def decode_marker(image, rect, scale):
    x, y, width, height = rect
    values = []
    for index in range(20):
        cx = round((x + (index + 0.5) * width / 20) * scale)
        cy = round((y + height / 2) * scale)
        if cx < 1 or cy < 1 or cx >= image.width - 1 or cy >= image.height - 1:
            return None
        patch = np.asarray(image.crop((cx - 1, cy - 1, cx + 2, cy + 2)).convert("RGB"), dtype=float)
        level = float(np.median(patch))
        if 55 < level < 200:
            return None
        values.append(int(level >= 200))
    if values[:2] != [0, 1] or values[18] == values[19]:
        return None
    parity = 0
    for bit in values[2:18]:
        parity ^= bit
    if parity != values[18]:
        return None
    return sum(bit << index for index, bit in enumerate(values[2:18]))


def extract(movie, output):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_frames", "-show_streams", "-of", "json", str(movie)], check=True, capture_output=True, text=True)
    data = json.loads(probe.stdout)
    subprocess.run(["ffmpeg", "-v", "error", "-i", str(movie), "-map", "0:v:0", "-fps_mode", "passthrough", str(output / "%06d.png")], check=True)
    files = sorted(output.glob("*.png"))
    timestamps = [float(frame["best_effort_timestamp_time"]) for frame in data["frames"] if "best_effort_timestamp_time" in frame]
    if len(files) != len(timestamps):
        raise LabError(f"decoded PNG count {len(files)} != PTS count {len(timestamps)}")
    frames = [{"path": str(file.name), "pts": t} for file, t in zip(files, timestamps)]
    result = {"streams": data["streams"], "cadence": cadence(timestamps), "frames": frames,
              "ptsAnomalies": {"duplicate": sum(b == a for a, b in zip(timestamps, timestamps[1:])),
                               "backwards": sum(b < a for a, b in zip(timestamps, timestamps[1:]))}}
    (output / "frames.json").write_text(json.dumps(result, indent=2))
    return result


def observe_marker(arguments):
    path, rect, scale = arguments
    with Image.open(path) as image:
        return decode_marker(image, rect, scale), image_metadata(image)


def map_frames(directory, rows, scenario):
    directory = Path(directory)
    data = json.loads((directory / "frames.json").read_text())
    markers = {}
    for row in rows:
        if row.get("k") == "lab_marker":
            markers.setdefault(row["sequence"], []).append(row["t"])
    o = origin(rows)
    mapped = []
    last = float("-inf")
    duplicates = 0
    metadata = None
    mapped_indices = []
    arguments = [(directory / frame["path"], scenario.get("marker", [8, 56, 100, 10]), scenario["canvas"]["scale"])
                 for frame in data["frames"]]
    with ThreadPoolExecutor(max_workers=4) as executor:
        for frame_index, (frame, observed) in enumerate(zip(data["frames"], executor.map(observe_marker, arguments))):
            sequence, properties = observed
            metadata = metadata or properties
            options = [t for t in markers.get(sequence, []) if t >= last - 1e-8]
            if not options:
                continue
            chosen = options[0]
            if abs(chosen - last) < 1e-8:
                duplicates += 1
            last = chosen
            mapped_indices.append(frame_index)
            mapped.append({**frame, "t": chosen - o, "sequence": sequence, "path": str(directory / frame["path"])})
    active_count = mapped_indices[-1] - mapped_indices[0] + 1 if mapped_indices else 0
    return {"frames": mapped, "decodedCount": len(data["frames"]), "mappedCount": len(mapped), "duplicateMarkers": duplicates,
            "imageMetadata": metadata, "cadence": data["cadence"], "activeDecodedCount": active_count,
            "leadTailFrames": len(data["frames"]) - active_count,
            "decodedMarkerCoverage": len(mapped) / active_count if active_count else 0,
            "ptsAnomalies": data.get("ptsAnomalies", {"duplicate": sum(b["pts"] == a["pts"] for a, b in zip(data["frames"], data["frames"][1:])),
                                                       "backwards": sum(b["pts"] < a["pts"] for a, b in zip(data["frames"], data["frames"][1:]))})}


def gesture_film_coverage(frames, rows, period):
    times = sorted(set(frame["t"] for frame in frames))
    o = origin(rows)
    output = []
    radius = min(max(period, 1 / 120), 0.05)
    for index, stroke in enumerate(strokes(rows)):
        first, last = stroke["points"][0], stroke["points"][-1]
        start = first.get("delivered_t", first["t"]) - o
        end = last.get("delivered_t", last["t"]) - o + 0.5
        intervals = [(max(start, t - radius), min(end, t + radius)) for t in times if start - radius <= t <= end + radius]
        covered, previous = 0.0, start
        for left, right in intervals:
            if right > max(left, previous):
                covered += right - max(left, previous)
            previous = max(previous, right)
        output.append({"stroke": index, "start": start, "end": end,
                       "coverage": covered / (end - start), "window": "down through release + 500 ms"})
    return output


def region_metrics(native, candidate, rect, scale):
    box = tuple(round(v * scale) for v in (rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]))
    a = np.asarray(native.crop(box).convert("RGB"), dtype=float)
    b = np.asarray(candidate.crop(box).convert("RGB"), dtype=float)
    difference = b - a
    absolute = np.abs(difference)
    ga = np.mean(a, axis=2)
    gb = np.mean(b, axis=2)
    edges = []
    for axis in (0, 1):
        if ga.shape[axis] > 1:
            edges.append(np.diff(gb, axis=axis) - np.diff(ga, axis=axis))
    return {"mae": float(np.mean(absolute)), "p95": float(np.percentile(absolute, 95)),
            "bias": np.mean(difference, axis=(0, 1)).tolist(), "nativeMean": np.mean(a, axis=(0, 1)).tolist(),
            "candidateMean": np.mean(b, axis=(0, 1)).tolist(),
            "edgeRms": float(np.sqrt(sum(np.sum(edge * edge) for edge in edges) / sum(edge.size for edge in edges))) if edges else 0,
            "nativeNearWhiteFraction": float(np.mean(a >= 254)), "candidateNearWhiteFraction": float(np.mean(b >= 254)),
            "profiles": {"horizontal": {"native": np.mean(ga, axis=0).tolist(), "candidate": np.mean(gb, axis=0).tolist()},
                         "vertical": {"native": np.mean(ga, axis=1).tolist(), "candidate": np.mean(gb, axis=1).tolist()}}}


def compare_pair(native_path, candidate_path, scenario):
    with Image.open(native_path) as native, Image.open(candidate_path) as candidate:
        a, b = image_metadata(native), image_metadata(candidate)
        expected = scenario["canvas"]
        size = (round(expected["width"] * expected["scale"]), round(expected["height"] * expected["scale"]))
        if native.size != size or candidate.size != size:
            raise LabError(f"image dimensions must be {size}; got {native.size}, {candidate.size}")
        regions = {region["id"]: region_metrics(native, candidate, region["rect"], expected["scale"]) for region in scenario.get("regions", [])}
        return {"nativeMetadata": a, "candidateMetadata": b, "colorProfileMatches": a["iccSha256"] == b["iccSha256"],
                "space": "encoded SDR RGB levels 0..255; HDR intensity is not inferred", "regions": regions}


def compare_transfer(native_black, native_white, candidate_black, candidate_white, scenario):
    paths = [native_black, native_white, candidate_black, candidate_white]
    arrays = []
    metadata = []
    expected = scenario["canvas"]
    size = (round(expected["width"] * expected["scale"]), round(expected["height"] * expected["scale"]))
    for path in paths:
        with Image.open(path) as image:
            if image.size != size:
                raise LabError(f"transfer image dimensions must be {size}")
            arrays.append(np.asarray(image.convert("RGB"), dtype=float))
            metadata.append(image_metadata(image))
    nc, nd, cc, cd = arrays
    native_transfer, candidate_transfer = (nd - nc) / 255, (cd - cc) / 255
    regions = {}
    for region in scenario.get("regions", []):
        l, t, w, h = region["rect"]
        scale = expected["scale"]
        view = np.s_[round(t * scale):round((t + h) * scale), round(l * scale):round((l + w) * scale)]
        a, b = native_transfer[view], candidate_transfer[view]
        regions[region["id"]] = {"nativeEffectiveTransfer": np.mean(a, axis=(0, 1)).tolist(),
                                  "candidateEffectiveTransfer": np.mean(b, axis=(0, 1)).tolist(),
                                  "transferRms": float(np.sqrt(np.mean((b - a) ** 2))),
                                  "blackLiftDifferenceRgb": np.mean(cc[view] - nc[view], axis=(0, 1)).tolist(),
                                  "nativeNegativeTransferFraction": float(np.mean(a < 0)),
                                  "candidateNegativeTransferFraction": float(np.mean(b < 0))}
    return {"space": "effective transfer in encoded SDR RGB; nonlinear tone mapping prevents interpreting this as physical alpha",
            "regions": regions, "metadata": metadata, "colorProfileMatches": len({m["iccSha256"] for m in metadata}) == 1}


def pair_metrics(arguments):
    return compare_pair(*arguments)


def pair_frames(native, candidate, scenario, start=0, end=float("inf")):
    pairs = []
    tolerance = scenario.get("filmToleranceMs", 25) / 1000
    candidates = [frame for frame in candidate if start <= frame["t"] <= end]
    times = np.array([f["t"] for f in candidates])
    used = set()
    for frame in native:
        if not candidates or not start <= frame["t"] <= end:
            continue
        index = int(np.argmin(np.abs(times - frame["t"])))
        other = candidates[index]
        if index in used or abs(other["t"] - frame["t"]) > tolerance:
            continue
        used.add(index)
        pairs.append({"t": frame["t"], "deltaMs": (other["t"] - frame["t"]) * 1000,
                      "native": frame["path"], "candidate": other["path"],
                      "nativePts": frame["pts"], "candidatePts": other["pts"],
                      "nativeSequence": frame["sequence"], "candidateSequence": other["sequence"]})
    with ThreadPoolExecutor(max_workers=4) as executor:
        results = executor.map(pair_metrics, [(pair["native"], pair["candidate"], scenario) for pair in pairs])
        for pair, metrics in zip(pairs, results):
            pair.update(metrics)
    return pairs


def compare_films(native_directory, candidate_directory, native_rows, candidate_rows, scenario, windows=None):
    a = map_frames(native_directory, native_rows, scenario)
    b = map_frames(candidate_directory, candidate_rows, scenario)
    pairs = pair_frames(a["frames"], b["frames"], scenario)
    failures = []
    tolerance = scenario.get("filmToleranceMs", 25) / 1000
    for window in windows or []:
        frames_a = [{**frame, "t": frame["t"] - window["nativeGlobalOffset"]} for frame in a["frames"]]
        frames_b = [{**frame, "t": frame["t"] - window["candidateGlobalOffset"]} for frame in b["frames"]]
        local_pairs = pair_frames(frames_a, frames_b, scenario, window["start"], window["end"])
        period = (a["cadence"].get("medianGapMs") or 1000 / 60) / 1000
        stroke = strokes(native_rows)[window["stroke"]]
        local_rows = [{**point, "delivered_t": point.get("delivered_t", point["t"]) - window["nativeOrigin"]}
                      for point in stroke["points"]]
        coverage = gesture_film_coverage(local_pairs, local_rows, period)[0]
        window["film"] = {"pairs": local_pairs, "pairedGestureCoverage": coverage,
                          "toleranceMs": tolerance * 1000,
                          "complete": coverage["coverage"] >= 0.8,
                          "note": "inspection only; global capture validity and drift are retained"}
    for side, data in (("native", a), ("candidate", b)):
        if data["decodedMarkerCoverage"] < 0.8:
            failures.append(f"{side} film: fewer than 80% frames have a valid marker")
        if data["ptsAnomalies"]["backwards"]:
            failures.append(f"{side} film: presentation timestamps go backwards")
        rows = native_rows if side == "native" else candidate_rows
        period = (data["cadence"].get("medianGapMs") or 1000 / 60) / 1000
        data["gestureCoverage"] = gesture_film_coverage(data["frames"], rows, period)
        for window in data["gestureCoverage"]:
            if window["coverage"] < 0.8:
                failures.append(f"{side} film: stroke {window['stroke']} has less than 80% temporal coverage")
    if not pairs:
        failures.append("film: no aligned frame pairs")
    paired_coverage = gesture_film_coverage(pairs, native_rows, (a["cadence"].get("medianGapMs") or 1000 / 60) / 1000)
    for window in paired_coverage:
        if window["coverage"] < 0.8:
            failures.append(f"paired film: stroke {window['stroke']} has less than 80% temporal coverage")
    for pair in pairs:
        if not pair["colorProfileMatches"]:
            failures.append("film: color profiles differ; color metrics need an explicit conversion")
            break
    for region in scenario.get("regions", []):
        for metric, limit in region.get("gates", {}).items():
            values = [p["regions"][region["id"]][metric] for p in pairs]
            if not values or max(values) > limit:
                failures.append(f"region {region['id']} {metric}: {max(values, default=None)} exceeds {limit}")
    return {"native": {k: v for k, v in a.items() if k != "frames"}, "candidate": {k: v for k, v in b.items() if k != "frames"},
            "pairs": pairs, "failures": failures, "toleranceMs": tolerance * 1000, "pairedGestureCoverage": paired_coverage}
