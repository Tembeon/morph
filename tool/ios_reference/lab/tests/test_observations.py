import copy
import json
from pathlib import Path
import unittest

from morph_lab.observations import check_windows
from morph_lab.scenario import LabError, validate


class ObservationTests(unittest.TestCase):
    def setUp(self):
        self.scenario = json.loads((Path(__file__).parents[1] / "scenarios/button-press-drag.json").read_text())
        step = next(step for step in self.scenario["steps"] if step["action"] == "gesture")
        self.scenario["observationWindows"] = [{"id": "press", "step": step["id"], "start": 0, "end": 0.5, "maxGapMs": 25,
                                                "tracks": [{"id": "button", "properties": ["left"]}]}]

    def rows(self, offset=0):
        rows = [{"k": "touch", "phase": 0, "t": offset + 1}]
        rows.extend({"k": "lab_sample", "t": offset + 1 + index / 100, "id": "button", "values": {"left": 141}}
                    for index in range(51))
        return rows

    def test_received_touch_alignment_keeps_complete_telemetry_separate_from_fidelity(self):
        result = check_windows(self.rows(), self.rows(100), self.scenario)
        self.assertTrue(result["passed"])
        self.assertIn("not optical", result["scope"])

    def test_dense_aggregate_cannot_hide_a_hole_in_a_critical_interval(self):
        rows = self.rows()
        rows = [row for row in rows if not 1.1 < row["t"] < 1.4]
        rows.extend({"k": "lab_sample", "t": 3 + index / 1000, "id": "button", "values": {"left": 141}}
                    for index in range(1000))
        result = check_windows(self.rows(), rows, self.scenario)
        self.assertFalse(result["passed"])
        self.assertGreater(result["windows"][0]["sides"]["candidate"]["button"]["left"]["maxGapMs"], 250)

    def test_missing_property_missing_down_and_unobserved_start_fail(self):
        for rows in ([row for row in self.rows() if row.get("k") != "touch"],
                     [{**row, "values": {}} if row.get("k") == "lab_sample" else row for row in self.rows()],
                     [row for row in self.rows() if row.get("k") == "touch" or row["t"] >= 1.2]):
            self.assertFalse(check_windows(self.rows(), rows, self.scenario)["passed"])

    def test_unknown_track_invalid_interval_and_ambiguous_gesture_are_rejected(self):
        validate(self.scenario)
        for change in ({"tracks": [{"id": "unknown", "properties": ["left"]}]}, {"end": 0}, {"maxGapMs": float("inf")}):
            scenario = copy.deepcopy(self.scenario)
            scenario["observationWindows"][0].update(change)
            with self.assertRaises(LabError):
                validate(scenario)
        scenario = copy.deepcopy(self.scenario)
        step = next(step for step in scenario["steps"] if step["id"] == scenario["observationWindows"][0]["step"])
        step["paths"] = [{"points": step["points"], "upAt": step["upAt"]}] * 2
        with self.assertRaisesRegex(LabError, "single-pointer"):
            validate(scenario)
