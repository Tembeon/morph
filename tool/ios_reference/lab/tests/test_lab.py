import copy
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image

from morph_lab.analysis import compare, compare_events, interpolate
from morph_lab.capture import device_lock
from morph_lab.images import compare_pair, compare_transfer, decode_marker, gesture_film_coverage, map_frames
from morph_lab.report import write_report
from morph_lab.scenario import LabError, digest, validate
from morph_lab.fitting import fit_spring


SCENE = Path(__file__).parents[1] / "scenarios/button-press-drag.json"


def trace(scenario, offset=0, jump=0, clip=False):
    rows = [{"k": "lab_start", "t": offset, "w": 402, "h": 874, "scale": 3, "rm": False, "rt": False, "sha256": digest(scenario)},
            {"k": "touch", "t": offset + 1, "phase": 0, "pointer": "p", "x": 201, "y": 402},
            {"k": "touch", "t": offset + 1.2, "phase": 3, "pointer": "p", "x": 201, "y": 402}]
    for index in range(90):
        t = offset + index / 60
        rows.extend([{"k": "lab_tick", "t": t, "cost_ms": 0.1},
                     {"k": "lab_sample", "t": t, "id": "button", "identity": "a", "values": {"left": 141 + (jump if index >= 65 else 0), "top": 380, "width": 120, "height": 44, "opacity": 1},
                      "clips": [[145, 380, 116, 44]] if clip else []}])
    return rows


def marker(sequence):
    image = Image.new("RGB", (160, 80), "#f2f2f7")
    bits = [(sequence >> index) & 1 for index in range(16)]
    parity = sum(bits) % 2
    pixels = image.load()
    for index, value in enumerate([0, 1] + bits + [parity, 1 - parity]):
        for x in range(8 + index * 5, 8 + (index + 1) * 5):
            for y in range(56, 66):
                pixels[x, y] = (255, 255, 255) if value else (0, 0, 0)
    return image


class ScenarioTests(unittest.TestCase):
    def setUp(self):
        self.scene = json.loads(SCENE.read_text())

    def test_all_shipped_scenarios_validate(self):
        for path in SCENE.parent.glob("*.json"):
            validate(json.loads(path.read_text()))

    def test_bad_time_and_offscreen_input_rejected(self):
        scene = copy.deepcopy(self.scene)
        scene["steps"][1]["points"][0]["t"] = float("nan")
        with self.assertRaises(LabError):
            validate(scene)
        scene = copy.deepcopy(self.scene)
        scene["steps"][1]["points"][0]["x"] = 402
        with self.assertRaises(LabError):
            validate(scene)

    def test_relative_anchor_allows_negative_offsets(self):
        scene = copy.deepcopy(self.scene)
        scene["steps"][1]["anchor"] = {"identifier": "glass"}
        scene["steps"][1]["points"][0]["x"] = -40
        validate(scene)

    def test_canonical_hash_ignores_dictionary_order(self):
        self.assertEqual(digest(self.scene), digest(dict(reversed(list(self.scene.items())))))


class AnalysisTests(unittest.TestCase):
    def setUp(self):
        self.scene = json.loads(SCENE.read_text())
        self.scene["tracks"] = [self.scene["tracks"][0]]
        self.scene["steps"] = [self.scene["steps"][1]]

    def test_clock_offset_does_not_change_geometry(self):
        result = compare(trace(self.scene, 800), trace(self.scene, 15), self.scene)
        self.assertTrue(result["passed"], result["failures"])
        self.assertAlmostEqual(result["geometry"]["boundsErrorPt"]["rms"], 0)

    def test_jump_and_clipping_are_detected(self):
        self.scene["gates"] = {"horizontalStepPt": 0.5, "geometryMaxPt": 0.5}
        result = compare(trace(self.scene), trace(self.scene, jump=8, clip=True), self.scene)
        self.assertFalse(result["passed"])
        self.assertEqual(result["geometry"]["maxHorizontalStepPt"], 8)
        self.assertEqual(result["geometry"]["maxClipLossPt"], 8)

    def test_missing_track_is_not_a_pass(self):
        candidate = [r for r in trace(self.scene) if r["k"] != "lab_sample"]
        result = compare(trace(self.scene), candidate, self.scene)
        self.assertFalse(result["passed"])
        self.assertIn("track button: no comparable samples", result["failures"])

    def test_empty_property_selection_is_not_evidence(self):
        candidate = trace(self.scene)
        for row in candidate:
            if row["k"] == "lab_sample":
                row["values"] = {}
        result = compare(trace(self.scene), candidate, self.scene)
        self.assertFalse(result["passed"])

    def test_stale_scene_and_unknown_accessibility_are_invalid(self):
        candidate = trace(self.scene)
        candidate[0]["sha256"] = "old build"
        candidate[0]["rt"] = None
        result = compare(trace(self.scene), candidate, self.scene)
        self.assertFalse(result["passed"])
        self.assertIn("accessibility setting rt was not read back", result["failures"])

    def test_missing_second_card_is_not_hidden_by_root_card(self):
        self.scene["tracks"][0]["native"]["all"] = True
        self.scene["tracks"][0]["flutter"]["all"] = True
        a, b = trace(self.scene), trace(self.scene)
        for rows in (a, b):
            for row in rows:
                if row.get("k") == "lab_sample":
                    row["id"] = "button/0"
        a.extend([{**r, "id": "button/1"} for r in a if r.get("k") == "lab_sample"])
        result = compare(a, b, self.scene)
        self.assertIn("track button/1: an observed instance is missing from one source", result["failures"])

    def test_no_received_gesture_and_missing_activation_require_review(self):
        rows = [r for r in trace(self.scene) if r.get("k") != "touch"]
        result = compare(rows, rows, self.scene)
        self.assertIn("native: received gesture count does not match the scenario", result["failures"])
        native = trace(self.scene)
        native.append({"k": "lab_event", "t": 1.2, "id": "glass", "e": "activate"})
        result = compare(native, trace(self.scene), self.scene)
        self.assertIn("event glass activate: counts differ", result["failures"])

    def test_source_and_delivery_clocks_are_not_equated(self):
        candidate = trace(self.scene)
        candidate[1]["delivered_t"] = candidate[1]["t"] + 0.03
        result = compare(trace(self.scene), candidate, self.scene)
        self.assertIn("touch clock bases differ; source time and delivery time cannot be equated", result["failures"])

    def test_callback_before_global_pointer_up_keeps_signed_dispatch_delta(self):
        rows = trace(self.scene)
        rows.append({"k": "lab_event", "t": 1.19995, "id": "glass", "e": "activate"})
        rows.append({"k": "lab_event", "t": 1.15, "id": "glass", "e": "changed"})
        groups = compare_events(rows, rows)["groups"]
        activation = next(g for g in groups if g["event"] == "activate")
        self.assertAlmostEqual(activation["native"][0]["fromUpMs"], -0.05)
        changing = next(g for g in groups if g["event"] == "changed")
        self.assertIsNone(changing["native"][0]["fromUpMs"])

    def test_cancellation_is_compared(self):
        candidate = trace(self.scene)
        candidate[2]["phase"] = 4
        result = compare(trace(self.scene), candidate, self.scene)
        self.assertIn("stroke 0: cancellation differs", result["failures"])

    def test_interpolation_never_bridges_drop_or_remount(self):
        a = {"t": 0, "identity": "first", "values": {"left": 0}}
        b = {"t": 1, "identity": "first", "values": {"left": 20}}
        self.assertIsNone(interpolate([a, b], [0, 1], 0.5))
        b.update(t=0.02, identity="second")
        self.assertIsNone(interpolate([a, b], [0, 0.02], 0.01))

    def test_reports_cannot_overwrite_a_reference(self):
        result = compare(trace(self.scene), trace(self.scene), self.scene)
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "report"
            page = write_report(result, self.scene, out)
            self.assertTrue(page.exists())
            with self.assertRaises(FileExistsError):
                write_report(result, self.scene, out)


class CaptureTests(unittest.TestCase):
    def test_lock_is_atomic_and_released_after_error(self):
        with tempfile.TemporaryDirectory() as temp:
            lock = Path(temp) / "lock"
            with self.assertRaises(RuntimeError):
                with device_lock("first", lock):
                    with self.assertRaises(LabError):
                        with device_lock("second", lock):
                            self.fail("stole phone")
                    self.assertIn("first", (lock / "owner").read_text())
                    raise RuntimeError()
            self.assertFalse(lock.exists())

    def test_marker_roundtrip_and_corruption(self):
        for sequence in (0, 1, 100, 32768, 65535):
            self.assertEqual(decode_marker(marker(sequence), [8, 56, 100, 10], 1), sequence)
        image = marker(4)
        for x in range(98, 103):
            for y in range(56, 66):
                image.putpixel((x, y), (0, 0, 0))
        self.assertIsNone(decode_marker(image, [8, 56, 100, 10], 1))

    def test_valid_markers_do_not_hide_missing_gesture_windows(self):
        rows = trace(json.loads(SCENE.read_text()))
        frames = [{"t": index / 60} for index in range(43)]
        complete = gesture_film_coverage(frames, rows, 1 / 60)
        self.assertAlmostEqual(complete[0]["coverage"], 1)
        partial = gesture_film_coverage(frames[20:25], rows, 1 / 60)
        self.assertLess(partial[0]["coverage"], 0.2)

    def test_real_pts_are_preserved_when_mapping(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            frames = []
            for index, pts in enumerate((0.0, 0.021, 0.083)):
                name = f"{index}.png"
                marker(index + 1).save(path / name)
                frames.append({"path": name, "pts": pts})
            (path / "frames.json").write_text(json.dumps({"frames": frames, "cadence": {}}))
            rows = [{"k": "start", "t": 100}] + [{"k": "lab_marker", "sequence": i + 1, "t": 100 + i / 60} for i in range(3)]
            result = map_frames(path, rows, {"canvas": {"scale": 1}})
            self.assertEqual([r["pts"] for r in result["frames"]], [0.0, 0.021, 0.083])
            self.assertAlmostEqual(result["frames"][2]["t"], 2 / 60)

    def test_region_color_error_and_dimensions(self):
        with tempfile.TemporaryDirectory() as temp:
            a, b = Path(temp) / "a.png", Path(temp) / "b.png"
            Image.new("RGB", (12, 12), (10, 20, 30)).save(a)
            Image.new("RGB", (12, 12), (20, 30, 40)).save(b)
            scene = {"canvas": {"width": 12, "height": 12, "scale": 1}, "regions": [{"id": "face", "rect": [0, 0, 12, 12]}]}
            result = compare_pair(a, b, scene)
            self.assertEqual(result["regions"]["face"]["mae"], 10)
            scene["canvas"]["width"] = 11
            with self.assertRaises(LabError):
                compare_pair(a, b, scene)

    def test_transfer_separates_additive_lift_from_transmission(self):
        with tempfile.TemporaryDirectory() as temp:
            paths = [Path(temp) / f"{i}.png" for i in range(4)]
            for path, level in zip(paths, (20, 220, 30, 230)):
                Image.new("RGB", (12, 12), (level, level, level)).save(path)
            scene = {"canvas": {"width": 12, "height": 12, "scale": 1}, "regions": [{"id": "face", "rect": [0, 0, 12, 12]}]}
            result = compare_transfer(*paths, scene)
            self.assertEqual(result["regions"]["face"]["transferRms"], 0)
            self.assertEqual(result["regions"]["face"]["blackLiftDifferenceRgb"], [10, 10, 10])


class FittingTests(unittest.TestCase):
    def test_recovers_spring_and_scores_an_independent_holdout(self):
        def recording(offset):
            rows = [{"k": "touch", "phase": 0, "t": offset}]
            for t in np.linspace(0, 1.2, 145):
                elapsed = max(0, t - 0.025)
                w = 2 * np.pi / 0.4
                d = 0.75
                wd = w * np.sqrt(1 - d * d)
                value = 1 - np.exp(-d * w * elapsed) * (np.cos(wd * elapsed) + d / np.sqrt(1 - d * d) * np.sin(wd * elapsed))
                rows.append({"k": "lab_sample", "id": "lift", "t": offset + float(t), "values": {"scaleX": float(value)}})
            return rows
        result = fit_spring(recording(10), "lift", "scaleX", 0, 1.2, recording(200))
        self.assertAlmostEqual(result["parameters"]["response"], 0.4, places=4)
        self.assertAlmostEqual(result["parameters"]["damping"], 0.75, places=4)
        self.assertAlmostEqual(result["parameters"]["delay"], 0.025, places=4)
        self.assertLess(result["holdout"]["rms"], 1e-5)
        self.assertTrue(result["requiresReview"])

    def test_constant_layout_does_not_identify_a_spring(self):
        scene = json.loads(SCENE.read_text())
        with self.assertRaises(LabError):
            fit_spring(trace(scene), "button", "width", -0.8, 0.4)


if __name__ == "__main__":
    unittest.main()
