"""UIKit's open-menu flex (iOS 27.0.1), replayed against a device capture.

Usage: python3 menu_flex_model.py FIXTURE [rec|spring]

FIXTURE is test/fixtures/ios27-device/menu/drag-out{,-upward}-flex.jsonl.
`rec` drives the pulse with UIKit's recorded translationY velocity, `spring`
with the nominal spring UIKit declares for that channel (0.574 / 0.548) run
in wall time, `stepped` with that spring as UIKit steps it while the finger
is down: the channel updates at 30 Hz and an update that retargets (the
finger moved) advances the spring by a fixed 1/60 s, an update that does not
by the elapsed time (observed live on iOS 27.0.1, menu-button.md).
The derivation notes are kept privately, outside the repository.
"""
import json
import math
import sys

THRESHOLD = 6000.0
IN_BOUNDS = 40.0
PULSE_NORMALIZATION = 8000.0
PULSE_X = 50.0
PULSE_Y = 32.0
PULSE_DRIFT = 0.7
MIN_SCALE, MAX_SCALE = 0.9, 1.1
RELEASE = (0.6, 0.5)
TRANSLATION_Y = (0.574, 0.548)
TRACKING_UPDATE = 1 / 30
RETARGET_STEP = 1 / 60


def targets(tx, ty, itx, ity, w, h, velocity, ay):
    kx = (abs(tx) - abs(itx) + abs(itx) / w * IN_BOUNDS) / THRESHOLD if tx else 0.0
    ky = (abs(ty) - abs(ity) + abs(ity) / h * IN_BOUNDS) / THRESHOLD if ty else 0.0
    p = velocity * ay / PULSE_NORMALIZATION
    fx = 1 - p * PULSE_X / w
    fy = 1 + p * PULSE_Y / h
    sx = min(max((1 + kx - ky) * fx, MIN_SCALE), MAX_SCALE)
    sy = min(max((1 - kx + ky) * fy, MIN_SCALE), MAX_SCALE)
    dx = math.copysign(kx * w, tx) if tx else 0.0
    dy = (math.copysign(ky * h, ty) if ty else 0.0) + ay * PULSE_DRIFT * PULSE_Y * p
    return sx, sy, dx, dy


def spring(x, v, target, response, damping, dt, steps=8):
    k = (2 * math.pi / response) ** 2
    c = 4 * math.pi * damping / response
    h = dt / steps
    for _ in range(steps):
        v += (k * (target - x) - c * v) * h
        x += v * h
    return x, v


def replay(rows, source):
    flex = [r for r in rows if r["k"] == "flex"]
    errors = {}
    state = [1.0, 1.0, 0.0, 0.0]
    speed = [0.0] * 4
    ty_x = ty_v = 0.0
    ty_goal = ty_at = None
    rest = None
    ay = 1.0
    drag = 0
    active = False
    ended = None
    previous = None
    for index, row in enumerate(flex):
        t = row["t"]
        dt = min(t - previous, 0.05) if previous is not None else 1 / 120
        previous = t
        pan = row.get("panState")
        if pan in (1, 2):
            if not active:
                active = True
                drag += 1
                ty_x = ty_v = 0.0
                ty_goal, ty_at = 0.0, t
                rest = row["frame"]
                # +1: the menu hangs below its button (captures put it in the
                # upper half), -1: above it.
                ay = 1.0 if rest[1] + rest[3] / 2 < 437 else -1.0
            tx, ty = row["translation"]
            itx, ity = row["internalTranslation"]
            if source == "rec":
                velocity = flex[index - 1].get("translationY_v", 0.0)
            elif source == "stepped":
                velocity = ty_v
                if t - ty_at >= TRACKING_UPDATE - 0.002:
                    step = RETARGET_STEP if ty != ty_goal else t - ty_at
                    ty_x, ty_v = spring(ty_x, ty_v, ty, *TRANSLATION_Y, step, steps=64)
                    ty_goal, ty_at = ty, t
            else:
                ty_x, ty_v = spring(ty_x, ty_v, ty, *TRANSLATION_Y, dt)
                velocity = ty_v
            w, h = row["bounds"]
            state = list(targets(tx, ty, itx, ity, w, h, velocity, ay))
            speed = [0.0] * 4
        else:
            if active:
                active = False
                ended = t
            for i, goal in enumerate((1.0, 1.0, 0.0, 0.0)):
                state[i], speed[i] = spring(state[i], speed[i], goal, *RELEASE, dt)
        if rest is None or (not active and (ended is None or t - ended > 1.3)):
            continue
        left, top, width, height = rest
        sx, sy, dx, dy = state
        cx = left + width / 2 + dx
        if ay > 0:
            near = top + dy
            predicted = (cx - width * sx / 2, near, cx + width * sx / 2, near + height * sy)
        else:
            near = top + height + dy
            predicted = (cx - width * sx / 2, near - height * sy, cx + width * sx / 2, near)
        fl, ft, fw, fh = row["frame"]
        observed = (fl, ft, fl + fw, ft + fh)
        errors.setdefault(drag, []).extend(o - p for o, p in zip(observed, predicted))
    return errors


def main():
    rows = [json.loads(line) for line in open(sys.argv[1])]
    source = sys.argv[2] if len(sys.argv) > 2 else "rec"
    errors = replay(rows, source)
    every = []
    for drag, values in errors.items():
        every += values
        rms = math.sqrt(sum(e * e for e in values) / len(values))
        print(f"drag {drag}: edge rms {rms:.3f} pt, max {max(abs(e) for e in values):.2f} pt")
    print(f"overall edge rms {math.sqrt(sum(e * e for e in every) / len(every)):.3f} pt")


if __name__ == "__main__":
    main()
