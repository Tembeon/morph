import hashlib
import json
import math
import re
from pathlib import Path


class LabError(ValueError):
    pass


def number(value, name, minimum=None):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise LabError(f"{name} must be a finite number")
    if minimum is not None and value < minimum:
        raise LabError(f"{name} must be >= {minimum}")
    return value


def identifier(value, name):
    if not isinstance(value, str) or not re.fullmatch(r"[a-zA-Z0-9_-]+", value):
        raise LabError(f"{name} must contain only letters, digits, _ or -")
    return value


def rectangle(value, name, canvas):
    if not isinstance(value, list) or len(value) != 4:
        raise LabError(f"{name} must be [left, top, width, height]")
    for i, part in enumerate(value):
        number(part, f"{name}[{i}]", 0)
    if value[2] <= 0 or value[3] <= 0:
        raise LabError(f"{name} must have positive dimensions")
    if value[0] + value[2] > canvas["width"] or value[1] + value[3] > canvas["height"]:
        raise LabError(f"{name} must fit inside the canvas")


def validate(data):
    if not isinstance(data, dict) or data.get("schema") != 1:
        raise LabError("scenario schema must be 1")
    identifier(data.get("id"), "id")
    canvas = data.get("canvas", {})
    for name in ("width", "height", "scale"):
        number(canvas.get(name), f"canvas.{name}", 1)
    if data.get("appearance") not in ("light", "dark"):
        raise LabError("appearance must be light or dark")
    background = data.get("background", {})
    if background.get("kind") not in ("solid", "grid", "ramp"):
        raise LabError("background.kind must be solid, grid or ramp")
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", background.get("color", "#F2F2F7")):
        raise LabError("background.color must be #RRGGBB")
    for name in ("cell", "period"):
        if name in background:
            number(background[name], f"background.{name}", 1)
    marker = data.get("marker", [8, 56, 100, 10])
    rectangle(marker, "marker", canvas)
    widgets = data.get("widgets", [])
    seen = set()
    for widget in widgets:
        wid = identifier(widget.get("id"), "widget.id")
        if wid in seen:
            raise LabError(f"duplicate widget {wid}")
        seen.add(wid)
        identifier(widget.get("kind"), "widget.kind")
        rectangle(widget.get("rect"), f"widget {wid}.rect", canvas)
        if "value" in widget:
            number(widget["value"], f"widget {wid}.value", 0)
        if widget["kind"] == "slider" and widget.get("value", 0.3) > 1:
            raise LabError("slider value must be <= 1")
        if widget["kind"] == "segmented" and not widget.get("labels"):
            raise LabError("segmented control needs labels")
    seen = set()
    for track in data.get("tracks", []):
        tid = identifier(track.get("id"), "track.id")
        if tid in seen:
            raise LabError(f"duplicate track {tid}")
        seen.add(tid)
        for side in ("native", "flutter"):
            selector = track.get(side)
            if not isinstance(selector, dict) or not selector:
                raise LabError(f"track {tid} needs {side} selector")
            if "class" in selector:
                try:
                    re.compile(selector["class"])
                except re.error as error:
                    raise LabError(f"track {tid}: {error}") from error
            if "index" in selector:
                if not isinstance(selector["index"], int) or selector["index"] < 0:
                    raise LabError("track index must be a nonnegative integer")
            if selector.get("source") not in (None, "view", "layer", "flex"):
                raise LabError("native source must be view, layer or flex")
            if "layerClass" in selector:
                try:
                    re.compile(selector["layerClass"])
                except re.error as error:
                    raise LabError(f"track {tid}: {error}") from error
        if "properties" in track and (not isinstance(track["properties"], list) or not track["properties"]):
            raise LabError("track properties must be a nonempty list")
    seen = set()
    for step in data.get("steps", []):
        sid = identifier(step.get("id"), "step.id")
        if sid in seen:
            raise LabError(f"duplicate step {sid}")
        seen.add(sid)
        action = step.get("action")
        number(step.get("after", 0), f"step {sid}.after", 0)
        if action == "gesture":
            paths = step.get("paths", [step])
            if not paths:
                raise LabError(f"step {sid} needs paths")
            for path in paths:
                anchor = path.get("anchor")
                if anchor is not None:
                    if not isinstance(anchor, dict) or not (anchor.get("identifier") or anchor.get("label")):
                        raise LabError("anchor needs identifier or label")
                    for fraction in ("fx", "fy"):
                        if fraction in anchor:
                            number(anchor[fraction], f"anchor.{fraction}", 0)
                            if anchor[fraction] > 1:
                                raise LabError("anchor fractions must be <= 1")
                points = path.get("points", [])
                if not points:
                    raise LabError(f"step {sid} needs points")
                last = -1
                for point in points:
                    t = number(point.get("t"), f"step {sid}.t", 0)
                    if t <= last:
                        raise LabError(f"step {sid} point times must increase")
                    last = t
                    for axis in ("x", "y"):
                        coordinate = number(point.get(axis), f"step {sid}.{axis}", None if anchor else 0)
                        extent = canvas["width" if axis == "x" else "height"]
                        if not anchor and coordinate >= extent:
                            raise LabError(f"step {sid} point is outside the screen")
                number(path.get("upAt"), f"step {sid}.upAt", last + 0.000001)
                if path.get("cancel", False):
                    raise LabError("native cancellation uses a background step; synthetic cancel is replay-only")
        elif action in ("wait", "background"):
            number(step.get("seconds"), f"step {sid}.seconds", 0.01)
        elif action != "shot":
            raise LabError(f"unknown action {action}")
    if not data.get("steps"):
        raise LabError("scenario needs steps")
    seen = set()
    for region in data.get("regions", []):
        rid = identifier(region.get("id"), "region.id")
        if rid in seen:
            raise LabError(f"duplicate region {rid}")
        seen.add(rid)
        rectangle(region.get("rect"), f"region {rid}.rect", canvas)
        for key, value in region.get("gates", {}).items():
            if key not in ("mae", "p95", "edgeRms"):
                raise LabError(f"unknown region gate {key}")
            number(value, f"region {rid}.gate {key}", 0)
    for key, value in data.get("gates", {}).items():
        if key not in ("geometryRmsPt", "geometryMaxPt", "horizontalStepPt", "clipLossPt", "touchPathRmsPt", "eventLatencyMs", "frameGapMs"):
            raise LabError(f"unknown gate {key}")
        number(value, f"gate {key}", 0)
    return data


def load(path):
    return validate(json.loads(Path(path).read_text()))


def digest(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def duration(data):
    total = 5.0
    for step in data["steps"]:
        if step["action"] == "gesture":
            total += max(path["upAt"] for path in step.get("paths", [step]))
        else:
            total += step.get("seconds", 0.5)
        total += step.get("after", 0)
    return total
