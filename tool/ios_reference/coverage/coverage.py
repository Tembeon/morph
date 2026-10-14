#!/usr/bin/env python3
"""Coverage ledger and scenario planner. Uses only the Python standard library.

Planning coverage is never counted as observed native fidelity. Imported evidence
must bind an individual obligation to an observed metric and a declared gate.
"""
import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path
import random
import sys
from collections import deque

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


class CoverageError(ValueError):
    """Invalid or unverifiable coverage data."""


def read(path):
    return json.loads(Path(path).read_text())


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def candidate_sources(root):
    paths = []
    for directory in (root / "lib", root / "hook", root / "example/lib"):
        paths.extend(path for path in directory.rglob("*") if path.is_file()
                     and (directory == root / "lib" or path.suffix in (".dart", ".frag", ".glsl", ".swift")))
    paths.extend(root / name for name in ("pubspec.yaml", "pubspec.lock", "example/pubspec.yaml", "example/pubspec.lock")
                 if (root / name).is_file())
    return {str(path.relative_to(root)): file_hash(path) for path in paths}


def require(condition, message):
    if not condition:
        raise CoverageError(message)


def unique(rows, label):
    require(isinstance(rows, list) and rows, f"{label}: nonempty list required")
    result = {}
    for row in rows:
        require(isinstance(row, dict) and isinstance(row.get("id"), str), f"{label}: missing id")
        require(row["id"] not in result, f"{label}: duplicate {row['id']}")
        result[row["id"]] = row
    return result


def validate_catalog(catalog):
    require(catalog.get("schema") == 1, "catalog schema must be 1")
    families = unique(catalog.get("families"), "families")
    templates = unique(catalog.get("requirements"), "requirements")
    profiles = unique(catalog.get("profiles"), "profiles")
    obligations = {}
    for family_id, family in families.items():
        require(family.get("delivery") in ("widget", "foundation", "platform-adapter"), f"{family_id}: delivery")
        require(type(family.get("decomposed")) is bool, f"{family_id}: explicit decomposition flag required")
        require(family.get("nativeApis"), f"{family_id}: native API inventory required")
        require(set(family.get("profiles", [])) <= profiles.keys() and family.get("profiles"), f"{family_id}: profiles")
        for requirement in templates.values():
            require(requirement.get("question") and requirement.get("dimension") and requirement.get("oracle"), "requirement needs question/dimension/oracle")
            key = f"{family_id}.{requirement['id']}"
            obligations[key] = {**requirement, "family": family_id, "profiles": family["profiles"]}
        for requirement in family.get("obligations", []):
            key = f"{family_id}.{requirement['id']}"
            require(key not in obligations, f"duplicate obligation {key}")
            require(requirement.get("question") and requirement.get("dimension"), f"{key}: question/dimension required")
            obligations[key] = {**requirement, "family": family_id, "profiles": family["profiles"]}
    require(isinstance(catalog.get("evidence"), list), "evidence list required")
    return families, profiles, obligations


def api_drift(baseline, current):
    require(baseline.get("schema") == current.get("schema") == 1, "API schema mismatch")
    before, after = baseline["symbols"], current["symbols"]
    return {
        "added": sorted(after.keys() - before.keys()),
        "removed": sorted(before.keys() - after.keys()),
        "changed": sorted(key for key in before.keys() & after.keys() if before[key] != after[key]),
    }


def resolve_artifact(record, base):
    path = (base / record["path"]).resolve()
    require(path.is_relative_to(base.resolve()), "artifact must stay inside evidence bundle")
    require(path.is_file() and file_hash(path) == record.get("sha256"), f"artifact missing or changed: {path}")
    return path


def nested(value, path):
    for key in path.split("/"):
        require(isinstance(value, dict) and key in value, f"observation missing: {path}")
        value = value[key]
    return value


def verify_evidence(record, obligations, profiles, root=ROOT):
    """Validate a bundle without promoting unrelated claims from a green report.

    Version one accepts telemetry metrics only. Optical, accessibility, haptic
    and perf obligations stay open until their respective adapters exist.
    """
    require(record.get("kind") == "lab-telemetry", "unsupported evidence kind")
    profile = profiles.get(record.get("profile"))
    require(profile is not None, "unknown evidence profile")
    require(record.get("environment") == profile["environment"], "capture environment differs from profile")
    base = Path(record["bundle"]).expanduser().resolve()
    scenario = read(resolve_artifact(record["scenario"], base))
    report = read(resolve_artifact(record["report"], base))
    require(report.get("schema") == 1 and report.get("scenario") == scenario.get("id"), "report/scenario mismatch")
    require(report.get("passed") is True and report.get("failures") == [], "comparison failed or missing result")
    require(report.get("fidelityGatesDeclared") is True, "evidence-only report cannot certify fidelity")
    for side in ("native", "candidate"):
        manifest = read(resolve_artifact(record[side + "Manifest"], base))
        require(manifest.get("status") == "captured", f"{side}: incomplete capture")
        require(manifest.get("coverageEnvironment") == record["environment"], f"{side}: environment provenance missing or different")
        require(manifest.get("scenarioSha256") == digest(scenario), f"{side}: scenario hash differs")
        metadata = report.get("quality", {}).get(side, {})
        require(metadata.get("errors") == [], f"{side}: invalid/missing capture quality")
        require(metadata.get("metadata", {}).get("sha256") == digest(scenario), f"{side}: trace scenario hash differs")
        if side == "native":
            os_version = str(metadata["metadata"].get("os", ""))
            require(os_version.split(".")[0] == str(profile["environment"]["nativeOSMajor"]), "native OS differs")
        settings = profile["readBack"]
        for key, expected in settings.items():
            require(metadata["metadata"].get(key) == expected, f"{side}: {key} not read back as expected")
        resolve_artifact(record[side + "Trace"], base)
        if side == "candidate":
            # A change anywhere in production sources invalidates this proof.
            hashes = manifest.get("sourceHashes", {})
            current = candidate_sources(root)
            def relevant(path):
                return path.startswith(("lib/", "hook/", "example/lib/")) or path in ("pubspec.yaml", "pubspec.lock", "example/pubspec.yaml", "example/pubspec.lock")
            require(current and {p: h for p, h in hashes.items() if relevant(p)} == current, "candidate source proof is stale or incomplete")
    claims = record.get("claims")
    require(isinstance(claims, list) and claims, "individual claims required")
    accepted = set()
    # These are the exact gate/metric relationships in morph_lab.analysis.
    metrics = {
        "geometryRmsPt": "geometry/boundsErrorPt/rms",
        "geometryMaxPt": "geometry/boundsErrorPt/max",
        "horizontalStepPt": "geometry/maxHorizontalStepPt",
        "clipLossPt": "geometry/maxClipLossPt",
        "touchPathRmsPt": "input/pathErrorPt/rms",
        "eventLatencyMs": "events/discreteLatencyDifferenceMs/max",
    }
    for claim in claims:
        obligation = claim.get("obligation")
        require(obligation in obligations, f"unknown obligation {obligation}")
        require(obligations[obligation].get("contractApproved") is True, "broad/unreviewed question cannot be certified")
        required_windows = obligations[obligation].get("observationWindows", [])
        acquisition = report.get("observationCoverage", {})
        require(isinstance(required_windows, list) and required_windows, "contract needs explicit observation windows")
        require(acquisition.get("declared") is True and acquisition.get("passed") is True, "critical telemetry acquisition is incomplete")
        scenario_windows = {window["id"] for window in scenario.get("observationWindows", [])}
        observed_windows = {window["id"] for window in acquisition.get("windows", []) if window.get("passed") is True}
        require(set(required_windows) <= scenario_windows & observed_windows, "required observation window missing or incomplete")
        require(record["profile"] in obligations[obligation].get("profiles", []), "profile is not applicable to this obligation")
        require(obligations[obligation].get("oracle") == "telemetry", f"{obligation}: this oracle cannot certify it")
        require(obligation not in accepted, f"duplicate claim {obligation}")
        gate = claim.get("gate")
        require(gate in metrics and claim.get("metric") == metrics[gate], "gate is unrelated to claimed metric")
        require(gate in scenario.get("gates", {}), f"declared gate missing: {gate}")
        limit = scenario["gates"][gate]
        actual = nested(report, metrics[gate])
        require(type(actual) in (int, float) and math.isfinite(actual), "metric absent or nonfinite")
        require(type(limit) in (int, float) and math.isfinite(limit) and 0 <= actual <= limit, "metric fails gate")
        # A reviewer must first link the concrete scenario to this obligation.
        require(digest(scenario) in obligations[obligation].get("scenarioHashes", []), "scenario not reviewed for this obligation")
        accepted.add(obligation)
    return accepted


def evaluate(catalog, root=ROOT):
    families, profiles, obligations = validate_catalog(catalog)
    covered = set()
    invalid = []
    for index, record in enumerate(catalog["evidence"]):
        try:
            for key in verify_evidence(record, obligations, profiles, root):
                covered.add((key, record["profile"]))
        except (CoverageError, OSError, KeyError, TypeError, ValueError) as error:
            invalid.append(f"evidence[{index}]: {error}")
    rows = []
    for key, family in families.items():
        required = {(oid, profile) for oid, obligation in obligations.items() if obligation["family"] == key for profile in family["profiles"]}
        missing = sorted(required - covered)
        rows.append({"family": key, "delivery": family["delivery"], "decomposed": family["decomposed"],
                     "verified": len(required & covered), "tracked": len(required), "missing": missing,
                     "ready": family["decomposed"] and not missing})
    return {"schema": 1, "ready": not invalid and all(row["ready"] for row in rows),
            "invalidEvidence": invalid, "families": rows,
            "warning": "Tracked obligations are a draft lower bound, not proof that every possible case was discovered."}


def validate_model(model):
    states = set(model["states"])
    require(model["initial"] in states, "initial state missing")
    edges = unique(model["transitions"], "transitions")
    require(len(states) == len(model["states"]), "duplicate state")
    for edge in edges.values():
        require(edge["from"] in states and edge["to"] in states, f"{edge['id']}: unknown state")
        require(edge.get("action"), f"{edge['id']}: action required")
    paths = {model["initial"]: []}
    pending = deque(paths)
    while pending:
        state = pending.popleft()
        for edge in edges.values():
            if edge["from"] == state and edge["to"] not in paths:
                paths[edge["to"]] = paths[state] + [edge["id"]]
                pending.append(edge["to"])
    require(states <= paths.keys(), f"unreachable states: {sorted(states - paths.keys())}")
    require(all(isinstance(values, list) and values and len({digest(v) for v in values}) == len(values)
                for values in model["factors"].values()), "factors need distinct values")
    return edges, paths


def covering_configs(factors, strength=2, seed=0):
    """Deterministic greedy covering array over the finite declared factors.

    No validity constraints are assumed. Add separate constrained profiles for
    incompatible combinations; do not silently discard cases.
    """
    keys = sorted(factors)
    require(1 <= strength <= len(keys), "invalid combination strength")
    size = math.prod(len(factors[key]) for key in keys)
    require(size <= 100000, "factor space too large; split into explicit risk groups")
    candidates = list(itertools.product(*(range(len(factors[key])) for key in keys)))
    random.Random(seed).shuffle(candidates)
    positions = list(itertools.combinations(range(len(keys)), strength))
    def tuples(row):
        return {(pos, tuple(row[p] for p in pos)) for pos in positions}
    remaining = set().union(*(tuples(row) for row in candidates))
    selected = []
    while remaining:
        best = max(candidates, key=lambda row: len(tuples(row) & remaining))
        selected.append({key: factors[key][best[i]] for i, key in enumerate(keys)})
        remaining.difference_update(tuples(best))
        candidates.remove(best)
    return selected


def plan(model, seed=0, strength=2):
    edges, paths = validate_model(model)
    cases = []
    # Ordered transition pairs expose return, interruption and rapid reopen.
    pairs = [(first, second) for first in edges.values() for second in edges.values() if first["to"] == second["from"]]
    configs = covering_configs(model["factors"], strength, seed)
    for config in configs:
        for first, second in pairs:
            sequence = paths[first["from"]] + [first["id"], second["id"]]
            cases.append({"id": f"{model['id']}-{len(cases):04d}", "config": config,
                          "transitions": sequence,
                          "actions": [edges[edge]["action"] for edge in sequence]})
    # Include terminal transitions even when they have no successor.
    represented = {edge for case in cases for edge in case["transitions"]}
    for edge in edges.values():
        if edge["id"] not in represented:
            for config in configs:
                cases.append({"id": f"{model['id']}-{len(cases):04d}", "config": config,
                              "transitions": paths[edge["from"]] + [edge["id"]],
                              "actions": [edges[e]["action"] for e in paths[edge["from"]] + [edge["id"]]]})
    return {"schema": 1, "modelSha256": digest(model), "seed": seed, "strength": strength,
            "status": "planned-unexecuted", "cases": cases,
            "unadaptedActions": sorted({action for case in cases for action in case["actions"] if action not in model.get("adaptedActions", [])})}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("check", "report"):
        command = sub.add_parser(name)
        command.add_argument("--catalog", type=Path, default=HERE / "catalog.json")
        command.add_argument("--api", type=Path)
        command.add_argument("--require-ready", action="store_true")
    command = sub.add_parser("plan")
    command.add_argument("model", type=Path)
    command.add_argument("--seed", type=int, default=0)
    command.add_argument("--strength", type=int, default=2)
    command.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "plan":
            result = plan(read(args.model), args.seed, args.strength)
            with args.out.open("x") as handle:
                json.dump(result, handle, indent=2, ensure_ascii=False)
            print(f"PLANNED {len(result['cases'])} cases; {len(result['unadaptedActions'])} actions need adapters")
            return
        result = evaluate(read(args.catalog))
        if args.api:
            result["apiDrift"] = api_drift(read(HERE / "api-baseline.json"), read(args.api))
        if args.command == "report":
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            count = sum(row["tracked"] for row in result["families"])
            print(f"INTEGRITY: {len(result['families'])} families, {count} tracked obligations; READINESS: {result['ready']}")
            for failure in result["invalidEvidence"]:
                print(f"  {failure}")
            if any(result.get("apiDrift", {}).values()):
                print("API DRIFT: review new/removed/changed declarations before updating the baseline")
                for kind, symbols in result["apiDrift"].items():
                    for symbol in symbols:
                        print(f"  {kind}: {symbol}")
        if result["invalidEvidence"] or any(result.get("apiDrift", {}).values()) or (args.require_ready and not result["ready"]):
            sys.exit(2)
    except (CoverageError, OSError, KeyError, TypeError, ValueError) as error:
        parser.exit(1, f"ERROR: {error}\n")


if __name__ == "__main__":
    main()
