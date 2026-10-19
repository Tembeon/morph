"""Analysis of an "abright" device capture (capture_abright.py output).

    python3 analyze_abright.py <capture dir> [<capture dir> ...]

Writes <dir>/report.md and <dir>/report.json:

- environment: system appearance, forced styles (must be none), the UIKit defaults read on the
  phone, whether the luma meters reported;
- per staircase, colour and coverage capture, a step table per bar: the content value, the
  render server's luma under the bar (meter), the bar's trait style, and from the screenshot
  the glass patch luma and the look (dark glyphs = light look); then the flips with their
  direction and the value that triggered them (flip luma up = dark -> light, down = light ->
  dark);
- per filmed step capture: the film aligned to the probe's steps through the content patch,
  then per step and crop (glass patch, glyphs, labels, status bar, home indicator) the latency
  from the content change, the transition's 5 / 50 / 95 percent times, the best curve fit, and
  the glass vs glyph onset and duration difference;
- per scroll capture: every style change with the meter luma and the content luma under the
  bar at that moment.

Luma: Rec. 709 weights on the encoded sRGB values (greys are exact whatever the weights; the
meter gives the render server's own value).
"""
import json
from pathlib import Path
import re
import subprocess
import sys

import numpy as np
from PIL import Image

WEIGHTS = np.array([0.2126, 0.7152, 0.0722])
SHOT = re.compile(r"(ab-[a-z]+-[a-z0-9-]+)-(\d{3})-([^_]+?)(?:_\d+_[0-9A-Fa-f-]+)?(?:\.png)?$")
CURVES = {
    "linear": None,
    "easeInOut": (0.42, 0.0, 0.58, 1.0),
    "default": (0.25, 0.1, 0.25, 1.0),
    "easeOut": (0.0, 0.0, 0.58, 1.0),
    "easeIn": (0.42, 0.0, 1.0, 1.0),
}


def rows(path):
    out = []
    for line in path.read_text().splitlines():
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return out


def luma(rgb):
    return float(np.dot(np.asarray(rgb[:3], dtype=float), WEIGHTS))


def action_value(action, width=402.0, height=874.0):
    """The content patch's value an action sets (None when it does not set one)."""
    name, _, arg = action.partition(":")
    vals = [float(v) for v in arg.split(",") if v]
    if name == "grey" and vals:
        return vals[0]
    if name == "rgb" and len(vals) == 3:
        return luma(vals)
    if name == "left" and vals:
        return 1.0 if 21.0 / width < vals[0] else 0.0
    if name in ("edge", "edgeb") and vals:
        y = vals[0] + height if vals[0] < 0 else vals[0]
        above = height / 2 < y
        return (1.0 if above else 0.0) if name == "edge" else (0.0 if above else 1.0)
    return None


def bezier(p, x):
    x1, y1, x2, y2 = p
    t = np.clip(np.asarray(x, dtype=float), 0, 1)
    for _ in range(8):
        bx = 3 * (1 - t) ** 2 * t * x1 + 3 * (1 - t) * t ** 2 * x2 + t ** 3
        d = 3 * (1 - t) ** 2 * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t ** 2 * (1 - x2)
        t = np.clip(t - (bx - x) / np.where(np.abs(d) < 1e-6, 1e-6, d), 0, 1)
    return 3 * (1 - t) ** 2 * t * y1 + 3 * (1 - t) * t ** 2 * y2 + t ** 3


GRID = np.linspace(0, 1, 1001)
TABLES = {name: (GRID if p is None else bezier(p, GRID)) for name, p in CURVES.items()}


def model(name, t, start, dur):
    if name == "spring":
        w = 2 * np.pi / max(dur, 1e-3)
        xs = np.clip(t - start, 0, None)
        return 1 - (1 + w * xs) * np.exp(-w * xs)
    return np.interp(np.clip((t - start) / dur, 0, 1), GRID, TABLES[name])


def fit_curve(t, q):
    """Best fit of a normalized progress q(t) (t from the content change) per curve family:
    UIKit cubic curves by duration, a critically damped spring by response."""
    t, q = np.asarray(t, dtype=float), np.asarray(q, dtype=float)
    if len(t) > 160:
        keep = np.linspace(0, len(t) - 1, 160).astype(int)
        t, q = t[keep], q[keep]
    hit = np.where(q >= 0.05)[0]
    t05 = float(t[hit[0]]) if len(hit) else 0.0
    out = []
    for name in list(CURVES) + ["spring"]:
        def search(starts, durs):
            best = (1e9, 0.0, 0.0)
            for s in starts:
                for d in durs:
                    err = float(np.sqrt(np.mean((model(name, t, s, d) - q) ** 2)))
                    if err < best[0]:
                        best = (err, s, d)
            return best
        err, s, d = search(np.arange(max(t05 - 0.12, 0), t05 + 0.07, 0.02), np.arange(0.05, 2.0, 0.02))
        err, s, d = search(np.arange(s - 0.02, s + 0.021, 0.005), np.arange(max(d - 0.04, 0.02), d + 0.041, 0.005))
        out.append({"curve": name, "rms": round(err, 4), "start": round(float(s), 3), ("response" if name == "spring" else "duration"): round(float(d), 3)})
    return sorted(out, key=lambda r: r["rms"])


def crop_luma(img, box, scale, mode="mean", against=None):
    x, y, w, h = [v * scale for v in box]
    a = img[int(round(y)):int(round(y + h)), int(round(x)):int(round(x + w)), :3].reshape(-1, 3) / 255.0
    if a.size == 0:
        return None
    lum = a @ WEIGHTS
    if mode == "mean":
        return float(lum.mean())
    lo, hi = float(np.percentile(lum, 5)), float(np.percentile(lum, 95))
    if against is None:
        return hi if abs(hi - 0.5) > abs(lo - 0.5) else lo
    return hi if abs(hi - against) > abs(lo - against) else lo


def last_before(items, t):
    best = None
    for item in items:
        if item["t"] <= t:
            best = item
        else:
            break
    return best


class Capture:
    def __init__(self, path):
        self.path = path
        self.name = path.stem.replace("rec-", "")
        self.rows = rows(path)
        self.start = next((r for r in self.rows if r.get("k") == "abstart"), {})
        self.go = next((r for r in self.rows if r.get("k") == "go"), None)
        crops = [r for r in self.rows if r.get("k") == "abcrops"]
        self.crops = crops[-1] if crops else None
        self.steps = [r for r in self.rows if r.get("k") == "step"]
        self.abs = {}
        for r in self.rows:
            if r.get("k") == "abs":
                self.abs.setdefault(r["bar"], []).append(r)
        self.lm = {}
        for r in self.rows:
            if r.get("k") == "lm":
                self.lm.setdefault(r["m"], []).append(r)
        self.offsets = [r for r in self.rows if r.get("k") == "off"]
        self.w = float(self.start.get("w", 402))
        self.h = float(self.start.get("h", 874))

    def step_end(self, i):
        if i + 1 < len(self.steps):
            return self.steps[i + 1]["t"]
        if i > 0:
            return self.steps[i]["t"] + (self.steps[i]["plan"] - self.steps[i - 1]["plan"])
        return self.steps[i]["t"] + 2.5

    def bars(self):
        return sorted(self.abs)

    def style(self, bar, t):
        r = last_before(self.abs.get(bar, []), t)
        if r is None:
            return None
        items = [it[1] for it in r.get("items", []) if it[0] == "g"]
        majority = max(set(items), key=items.count) if items else None
        return {"bar": r["uis"], "glyphs": majority}

    def meter(self, name, t):
        r = last_before(self.lm.get(name, []), t)
        return None if r is None else r["l"]


def environment(caps, theme):
    notes = []
    for c in caps:
        s = c.start
        if not s:
            notes.append(f"{c.name}: no abstart row")
            continue
        if s.get("override", 0) != 0 or s.get("probeDark"):
            notes.append(f"{c.name}: the window's style was forced (override {s.get('override')}, PROBE_DARK '{s.get('probeDark')}'): luma tracking is off, discard")
        expected = {"light": 1, "dark": 2}.get(theme)
        if expected and s.get("sys") != expected:
            notes.append(f"{c.name}: system style {s.get('sys')} but the run was tagged {theme}")
    first = next((c.start for c in caps if c.start), {})
    return {"os": first.get("os"), "sys": first.get("sys"), "defaults": first.get("defaults"), "args": first.get("args"),
            "meters": first.get("meters"), "meterRows": sum(len(v) for c in caps for v in c.lm.values()), "notes": notes}


def shots_for(capture_dir):
    found = {}
    for manifest in capture_dir.glob("*/attachments/manifest.json"):
        folder = manifest.parent

        def walk(node):
            if isinstance(node, dict):
                file = node.get("exportedFileName")
                name = node.get("suggestedHumanReadableName") or node.get("name") or file
                if file and name:
                    m = SHOT.match(Path(name).name) or SHOT.match(Path(file).name)
                    if m:
                        found.setdefault(m.group(1), {})[int(m.group(2))] = folder / file
                for v in node.values():
                    walk(v)
            elif isinstance(node, list):
                for v in node:
                    walk(v)

        walk(json.loads(manifest.read_text()))
    return found


def look_from_shot(cap, path):
    img = np.asarray(Image.open(path).convert("RGB"))
    scale = img.shape[1] / cap.w
    out = {"content": crop_luma(img, cap.crops["content"], scale)}
    for bar, spec in cap.crops["bars"].items():
        patches = [crop_luma(img, p, scale) for p in spec["patches"]]
        patches = [p for p in patches if p is not None]
        glass = float(np.median(patches)) if patches else None
        glyphs = [crop_luma(img, g, scale, "extreme", glass) for g in spec["glyphs"]]
        glyphs = [g for g in glyphs if g is not None]
        if bar == "tab" and len(glyphs) > 1:
            glyphs = glyphs[1:]
        glyph = float(np.median(glyphs)) if glyphs else None
        look = None if glass is None or glyph is None else ("dark" if glyph > glass else "light")
        out[bar] = {"glass": None if glass is None else round(glass, 4), "glyph": None if glyph is None else round(glyph, 4), "look": look}
    return out


def flips(sequence):
    """(index, from, to) where a state changes between consecutive steps."""
    out = []
    prev = None
    for i, state in sequence:
        if state is None:
            continue
        if prev is not None and state != prev[1]:
            out.append((i, prev[1], state))
        prev = (i, state)
    return out


def step_table(cap, shots):
    table = []
    for i, step in enumerate(cap.steps):
        end = cap.step_end(i) - 0.05
        row = {"i": i, "a": step["a"], "value": action_value(step["a"], cap.w, cap.h)}
        for bar in cap.bars():
            st = cap.style(bar, end)
            row[bar] = {"uis": st and st["bar"], "glyphUis": st and st["glyphs"], "meter": cap.meter(bar, end)}
        if shots and i in shots and cap.crops:
            look = look_from_shot(cap, shots[i])
            row["contentShot"] = look.pop("content")
            for bar, v in look.items():
                row.setdefault(bar, {}).update(v)
        table.append(row)
    return table


def flip_summary(cap, table):
    out = {}
    for bar in cap.bars():
        for signal, key in [("trait", "glyphUis"), ("look", "look")]:
            seq = [(r["i"], r.get(bar, {}).get(key)) for r in table]
            events = []
            for i, a, b in flips(seq):
                prev = table[i - 1]["value"] if i > 0 else None
                events.append({"step": i, "action": table[i]["a"], "from": a, "to": b, "value": table[i]["value"], "previous": prev,
                               "meter": table[i].get(bar, {}).get("meter"),
                               "direction": "up" if (prev is not None and table[i]["value"] is not None and table[i]["value"] > prev) else "down"})
            if events:
                out.setdefault(bar, {})[signal] = events
    return out


def film_series(movie, boxes, scale):
    """Per crop name: (pts array, luma array of the crop's mean or glyph extreme)."""
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time", "-of", "csv=p=0", str(movie)],
                           capture_output=True, text=True, check=True)
    pts = np.array([float(x.split(",")[0]) for x in probe.stdout.split() if x.strip()])
    names = list(boxes)
    parts = [f"[0]split={len(names)}" + "".join(f"[s{k}]" for k in range(len(names)))]
    sizes = []
    for k, name in enumerate(names):
        x, y, w, h = [int(round(v * scale)) for v in boxes[name]]
        w, h = max(w, 2) // 2 * 2, max(h, 2) // 2 * 2
        sizes.append((w, h))
        parts.append(f"[s{k}]crop={w}:{h}:{x}:{y}[c{k}]")
    tmp = movie.parent / "crops"
    tmp.mkdir(exist_ok=True)
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", str(movie), "-filter_complex", ";".join(parts)]
    for k in range(len(names)):
        cmd += ["-map", f"[c{k}]", "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", str(tmp / f"{k}.raw")]
    subprocess.run(cmd, check=True)
    out = {}
    for k, name in enumerate(names):
        w, h = sizes[k]
        raw = np.fromfile(tmp / f"{k}.raw", dtype=np.uint8)
        frames = raw.reshape(-1, h * w, 3) / 255.0
        lum = frames @ WEIGHTS
        n = min(len(pts), len(lum))
        if name.startswith("glyph"):
            series = np.where(np.abs(np.percentile(lum[:n], 95, axis=1) - 0.5) > np.abs(np.percentile(lum[:n], 5, axis=1) - 0.5),
                              np.percentile(lum[:n], 95, axis=1), np.percentile(lum[:n], 5, axis=1))
        else:
            series = lum[:n].mean(axis=1)
        out[name] = (pts[:n], series)
    return out


def align(cap, t_film, content):
    """Offset film time - probe time from the content patch's changes against the steps."""
    changes = []
    for k in range(1, len(content)):
        if abs(content[k] - content[k - 1]) > 0.04:
            if not changes or t_film[k] - changes[-1] > 0.15:
                changes.append(t_film[k])
    expected = [(s["t"], action_value(s["a"], cap.w, cap.h)) for s in cap.steps]
    times = [t for i, (t, v) in enumerate(expected) if v is not None and (i == 0 or expected[i - 1][1] is None or abs(v - expected[i - 1][1]) > 0.05)]
    if not changes or not times:
        return None, 0
    best = (None, 0, 1e9)
    for f in changes:
        for t in times:
            off = f - t
            hits = [min(abs(c - (tt + off)) for c in changes) for tt in times]
            n = sum(1 for d in hits if d < 0.06)
            spread = float(np.median([d for d in hits if d < 0.06])) if n else 1e9
            if n > best[1] or (n == best[1] and spread < best[2]):
                best = (off, n, spread)
    return (None if best[0] is None else float(best[0])), best[1]


def transitions(cap, series, offset):
    t_film, content = series["content"]
    out = []
    for i, step in enumerate(cap.steps):
        v = action_value(step["a"], cap.w, cap.h)
        prev = action_value(cap.steps[i - 1]["a"], cap.w, cap.h) if i else None
        if v is None or prev is None or abs(v - prev) < 0.05:
            continue
        t_step = step["t"] + offset
        end = cap.step_end(i) + offset
        idx = np.where((t_film > t_step - 0.1) & (t_film < t_step + 0.4))[0]
        jumps = [k for k in idx if k > 0 and abs(content[k] - content[k - 1]) > 0.04]
        if not jumps:
            continue
        t0 = t_film[jumps[0]]
        entry = {"i": i, "a": step["a"], "from": prev, "to": v, "contentFrame": round(float(t0 - t_step), 4), "crops": {}}
        for name, (tf, val) in series.items():
            if name == "content":
                continue
            before = val[(tf > t0 - 0.5) & (tf < t0 - 0.02)]
            imm = val[(tf > t0 + 0.02) & (tf < t0 + 0.09)]
            after = val[(tf > end - 0.5) & (tf < end - 0.05)]
            if len(before) == 0 or len(after) == 0:
                continue
            vb, va = float(np.median(before)), float(np.median(after))
            vi = float(np.median(imm)) if len(imm) else vb
            res = {"before": round(vb, 4), "immediate": round(vi, 4), "after": round(va, 4)}
            if abs(va - vi) >= 0.03:
                sel = (tf >= t0) & (tf < end - 0.05)
                tt, q = tf[sel] - t0, (val[sel] - vi) / (va - vi)
                def first(level):
                    hit = np.where(q >= level)[0]
                    return round(float(tt[hit[0]]), 4) if len(hit) else None
                res.update({"t05": first(0.05), "t50": first(0.5), "t95": first(0.95)})
                if len(tt) > 5:
                    res["fit"] = fit_curve(tt, q)[:3]
            entry["crops"][name] = res
        glass = [entry["crops"][n] for n in entry["crops"] if n.startswith("glass") and "t50" in entry["crops"][n]]
        glyph = [entry["crops"][n] for n in entry["crops"] if n.startswith("glyph") and "t50" in entry["crops"][n]]
        if glass and glyph:
            def med(items, key):
                vals = [x[key] for x in items if x.get(key) is not None]
                return float(np.median(vals)) if vals else None
            entry["sync"] = {k: (None if med(glyph, k) is None or med(glass, k) is None else round(med(glyph, k) - med(glass, k), 4))
                             for k in ("t05", "t50", "t95")}
        out.append(entry)
    return out


def scroll_events(cap):
    bands = cap.start.get("bands", [])
    top = cap.start.get("scrollTop", 0.0)

    def content_under(y_window, t):
        off = last_before(cap.offsets, t)
        y = y_window - top + (off["y"] if off else cap.start.get("offset", 0.0))
        for b in bands:
            if b[0] <= y < b[1]:
                return luma(b[2:5]) if b[2] >= 0 else None
        return None

    out = {}
    for bar, items in cap.abs.items():
        frame = cap.crops["bars"].get(bar, {}).get("frame") if cap.crops else None
        if not frame:
            continue
        mid = frame[1] + frame[3] / 2
        prev = None
        events = []
        for r in items:
            glyphs = [it[1] for it in r.get("items", []) if it[0] == "g"]
            state = max(set(glyphs), key=glyphs.count) if glyphs else r["uis"]
            if prev is not None and state != prev:
                events.append({"t": round(r["t"] - (cap.go["t"] if cap.go else 0), 3), "to": state, "meter": cap.meter(bar, r["t"]),
                               "contentUnderBar": content_under(mid, r["t"])})
            prev = state
        out[bar] = events
    return out


def film_boxes(cap):
    boxes = {"content": cap.crops["content"], "status": cap.crops["status"], "home": cap.crops["home"]}
    for bar, spec in cap.crops["bars"].items():
        for k, p in enumerate(spec["patches"][:3]):
            boxes[f"glass-{bar}-{k}"] = p
        glyphs = spec["glyphs"][1:4] if bar == "tab" else spec["glyphs"][:3]
        for k, g in enumerate(glyphs):
            boxes[f"glyph-{bar}-{k}"] = g
        for k, label in enumerate(spec["labels"][:2]):
            boxes[f"label-{bar}-{k}"] = label
    return boxes


def analyse(capture_dir):
    commands = json.loads((capture_dir / "commands.json").read_text()) if (capture_dir / "commands.json").exists() else {}
    theme = commands.get("theme")
    tag = theme or "sys"
    caps = [Capture(p) for p in sorted((capture_dir / "rows").rglob(f"rec-ab-{tag}-*.jsonl"))]
    shots = shots_for(capture_dir)
    report = {"capture": str(capture_dir), "theme": theme, "environment": environment(caps, theme), "captures": {}}
    films = {p.parent.name: p for p in capture_dir.glob("*/movie.mov")}
    film_of = {"steps": "steps", "steps-static": "steps", "hold": "steps", "hold-static": "steps", "stripes-300": "scroll",
               "stripes-100": "scroll", "stripes-mid": "scroll", "ladder": "scroll", "search-tab": "search", "search-toolbar": "search",
               "flag-steps": "pocketflag", "flag-hold": "pocketflag"}
    for cap in caps:
        short = cap.name.split("-", 2)[2] if cap.name.count("-") >= 2 else cap.name
        entry = {"bars": cap.bars(), "steps": len(cap.steps)}
        table = step_table(cap, shots.get(cap.name, {}))
        entry["table"] = table
        entry["flips"] = flip_summary(cap, table)
        if short.startswith(("stripes", "ladder")):
            entry["scroll"] = scroll_events(cap)
        movie = films.get(film_of.get(short, ""))
        if movie and cap.crops:
            try:
                scale = None
                probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width", "-of", "csv=p=0", str(movie)],
                                       capture_output=True, text=True, check=True)
                scale = float(probe.stdout.strip()) / cap.w
                series = film_series(movie, film_boxes(cap), scale)
                offset, matched = align(cap, *series["content"])
                entry["film"] = {"movie": str(movie), "scale": scale, "offset": offset, "matchedSteps": matched}
                if offset is not None and not short.startswith(("stripes", "ladder")):
                    entry["transitions"] = transitions(cap, series, offset)
            except (subprocess.CalledProcessError, ValueError, KeyError) as error:
                entry["film"] = {"movie": str(movie), "error": str(error)}
        report["captures"][cap.name] = entry
    (capture_dir / "report.json").write_text(json.dumps(report, indent=1) + "\n")
    (capture_dir / "report.md").write_text(markdown(report))
    print(f"wrote {capture_dir / 'report.md'}")


def markdown(report):
    env = report["environment"]
    lines = [f"# abright capture {report['capture']}", "", f"Theme {report['theme']}, iOS {env.get('os')}, system style {env.get('sys')}.",
             f"UIKit defaults read on the phone: {env.get('defaults')}. Launch arguments: {env.get('args')}.",
             f"Luma meters: {env.get('meters')}, {env.get('meterRows')} rows.", ""]
    lines += [f"- WARNING {n}" for n in env.get("notes", [])]
    for name, cap in report["captures"].items():
        lines += ["", f"## {name}", ""]
        for bar, signals in cap.get("flips", {}).items():
            for signal, events in signals.items():
                for e in events:
                    lines.append(f"- {bar} {signal}: {e['from']} -> {e['to']} at step {e['step']} `{e['action']}` "
                                 f"(value {e['value']}, previous {e['previous']}, {e['direction']}, meter {e['meter']})")
        if not cap.get("flips"):
            lines.append("- no flip in any bar (trait or screenshot look)")
        for t in cap.get("transitions", []):
            crops = ", ".join(f"{k}: t05 {v.get('t05')} t50 {v.get('t50')} t95 {v.get('t95')} fit {v['fit'][0]['curve'] if v.get('fit') else '-'}"
                              for k, v in t["crops"].items() if "t50" in v)
            lines.append(f"- step {t['i']} {t['from']} -> {t['to']}: {crops or 'no delayed change'}; sync glyph - glass {t.get('sync')}")
        for bar, events in cap.get("scroll", {}).items():
            for e in events:
                lines.append(f"- scroll {bar}: to {e['to']} at {e['t']} s, meter {e['meter']}, content under the bar {e['contentUnderBar']}")
        film = cap.get("film")
        if film:
            lines.append(f"- film: {film}")
        if cap.get("table") and any("look" in r.get(b, {}) for r in cap["table"] for b in cap["bars"]):
            lines += ["", "| step | action | " + " | ".join(f"{b} uis / look / glass / meter" for b in cap["bars"]) + " |",
                      "|---|---|" + "---|" * len(cap["bars"])]
            for r in cap["table"]:
                cells = [f"{r.get(b, {}).get('glyphUis')} / {r.get(b, {}).get('look')} / {r.get(b, {}).get('glass')} / {r.get(b, {}).get('meter')}" for b in cap["bars"]]
                lines.append(f"| {r['i']} | `{r['a']}` | " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    for arg in sys.argv[1:]:
        analyse(Path(arg).resolve())
