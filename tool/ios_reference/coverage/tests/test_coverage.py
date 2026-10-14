import copy
import itertools
import json
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import coverage as ledger


class PlanningTests(unittest.TestCase):
    def test_pairwise_array_replays_and_really_covers_all_pairs(self):
        factors = {"appearance": ["light", "dark"], "size": [0, 1, 2], "direction": ["ltr", "rtl"], "effects": ["normal", "rm", "rt"]}
        rows = ledger.covering_configs(factors, seed=128)
        self.assertEqual(rows, ledger.covering_configs(factors, seed=128))
        for a, b in itertools.combinations(factors, 2):
            self.assertEqual({(row[a], row[b]) for row in rows}, set(itertools.product(factors[a], factors[b])))
        self.assertLess(len(rows), 36)

    def test_menu_sequences_are_reachable_and_cover_ordered_transition_pairs(self):
        model = ledger.read(HERE / "menu-model.json")
        plan = ledger.plan(model, seed=11)
        edges = {edge["id"]: edge for edge in model["transitions"]}
        observed = set()
        for case in plan["cases"]:
            state = model["initial"]
            for transition in case["transitions"]:
                edge = edges[transition]
                self.assertEqual(edge["from"], state)
                state = edge["to"]
            observed.update(zip(case["transitions"], case["transitions"][1:]))
        expected = {(a["id"], b["id"]) for a in edges.values() for b in edges.values() if a["to"] == b["from"]}
        self.assertTrue(expected <= observed)
        self.assertEqual(plan["status"], "planned-unexecuted")
        self.assertTrue(plan["unadaptedActions"])

    def test_unreachable_state_is_not_silently_skipped(self):
        model = ledger.read(HERE / "menu-model.json")
        model["states"].append("orphan")
        with self.assertRaisesRegex(ledger.CoverageError, "unreachable"):
            ledger.plan(model)

    def test_new_api_default_and_removed_member_require_review(self):
        baseline = {"schema": 1, "symbols": {"Widget": {"parameters": [{"default": "false"}], "members": ["old"]}}}
        current = copy.deepcopy(baseline)
        current["symbols"]["Widget"]["parameters"][0]["default"] = "true"
        current["symbols"]["Widget"]["members"] = []
        current["symbols"]["New"] = {}
        self.assertEqual(ledger.api_drift(baseline, current), {"added": ["New"], "removed": [], "changed": ["Widget"]})

    def test_draft_catalog_cannot_report_readiness(self):
        result = ledger.evaluate(ledger.read(HERE / "catalog.json"))
        self.assertFalse(result["ready"])
        self.assertEqual(result["invalidEvidence"], [])
        self.assertTrue(all(row["missing"] and not row["ready"] for row in result["families"]))


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "lib").mkdir()
        (self.root / "lib/control.dart").write_text("source version one")
        self.scenario = {"schema": 1, "id": "menu-test", "gates": {"geometryMaxPt": 1.0}}
        self.environment = {"nativeOSMajor": 27, "nativeTarget": "simulator", "appearance": "light"}
        self.profiles = {"sim": {"environment": self.environment, "readBack": {"rm": False, "rt": False}}}
        self.obligations = {"menu.root": {"oracle": "telemetry", "contractApproved": True, "profiles": ["sim"], "scenarioHashes": [ledger.digest(self.scenario)]}}
        self.record = {"kind": "lab-telemetry", "bundle": str(self.root), "profile": "sim", "environment": self.environment,
                       "claims": [{"obligation": "menu.root", "gate": "geometryMaxPt", "metric": "geometry/boundsErrorPt/max"}]}
        self.report = {"schema": 1, "scenario": "menu-test", "passed": True, "failures": [], "fidelityGatesDeclared": True,
                       "geometry": {"boundsErrorPt": {"max": 0.5}},
                       "quality": {side: {"errors": [], "metadata": {"sha256": ledger.digest(self.scenario), "rm": False, "rt": False, "os": "27.0"}}
                                   for side in ("native", "candidate")}}
        self.manifest = {"status": "captured", "scenarioSha256": ledger.digest(self.scenario), "coverageEnvironment": self.environment,
                         "sourceHashes": {"lib/control.dart": ledger.file_hash(self.root / "lib/control.dart")}}
        self.save("scenario", self.scenario)
        self.save("report", self.report)
        for side in ("native", "candidate"):
            self.save(side + "Manifest", self.manifest)
            self.save(side + "Trace", [{"k": "lab_start"}])

    def save(self, role, value):
        path = self.root / (role + ".json")
        path.write_text(json.dumps(value))
        self.record[role] = {"path": path.name, "sha256": ledger.file_hash(path)}

    def verify(self):
        return ledger.verify_evidence(self.record, self.obligations, self.profiles, self.root)

    def test_individual_telemetry_claim_is_accepted(self):
        self.assertEqual(self.verify(), {"menu.root"})

    def test_green_report_without_fidelity_gates_is_rejected(self):
        self.report["fidelityGatesDeclared"] = False
        self.save("report", self.report)
        with self.assertRaisesRegex(ledger.CoverageError, "evidence-only"):
            self.verify()

    def test_passed_flag_cannot_override_missing_or_failed_metric(self):
        for value in (None, 5, float("nan")):
            self.report["geometry"]["boundsErrorPt"]["max"] = value
            self.save("report", self.report)
            with self.assertRaises(ledger.CoverageError):
                self.verify()

    def test_artifact_change_and_candidate_edit_invalidate_evidence(self):
        (self.root / "candidateTrace.json").write_text("changed")
        with self.assertRaisesRegex(ledger.CoverageError, "artifact missing or changed"):
            self.verify()
        self.save("candidateTrace", [])
        (self.root / "lib/control.dart").write_text("source version two")
        with self.assertRaisesRegex(ledger.CoverageError, "stale"):
            self.verify()

    def test_deleted_candidate_file_invalidates_evidence(self):
        self.manifest["sourceHashes"]["lib/deleted.dart"] = "old hash"
        self.save("candidateManifest", self.manifest)
        with self.assertRaisesRegex(ledger.CoverageError, "stale"):
            self.verify()

    def test_dependency_or_harness_change_invalidates_evidence(self):
        (self.root / "pubspec.lock").write_text("new dependency resolution")
        with self.assertRaisesRegex(ledger.CoverageError, "stale"):
            self.verify()

    def test_geometry_cannot_certify_optics_or_unreviewed_scenario(self):
        self.obligations["menu.root"]["oracle"] = "optical-contract"
        with self.assertRaisesRegex(ledger.CoverageError, "oracle"):
            self.verify()
        self.obligations["menu.root"] = {"oracle": "telemetry", "contractApproved": True, "profiles": ["sim"], "scenarioHashes": []}
        with self.assertRaisesRegex(ledger.CoverageError, "not reviewed"):
            self.verify()

    def test_changed_environment_or_missing_settings_readback_is_rejected(self):
        self.manifest["coverageEnvironment"] = {**self.environment, "nativeTarget": "device"}
        self.save("nativeManifest", self.manifest)
        with self.assertRaisesRegex(ledger.CoverageError, "environment"):
            self.verify()

    def test_path_escape_is_rejected(self):
        self.record["report"]["path"] = "../report.json"
        with self.assertRaisesRegex(ledger.CoverageError, "inside evidence bundle"):
            self.verify()

    def test_approved_scenario_does_not_close_a_broad_unreviewed_question(self):
        self.obligations["menu.root"]["contractApproved"] = False
        with self.assertRaisesRegex(ledger.CoverageError, "unreviewed question"):
            self.verify()


if __name__ == "__main__":
    unittest.main()
