import argparse
import json
from pathlib import Path
import sys

from .analysis import cadence, compare, read_rows
from .capture import capture
from .images import compare_films, compare_pair, compare_transfer, extract
from .report import write_report
from .scenario import LabError, digest, load
from .fitting import fit_spring


def main():
    parser = argparse.ArgumentParser(description="Shared native/Flutter widget measurement laboratory")
    sub = parser.add_subparsers(dest="command", required=True)
    validate = sub.add_parser("validate")
    validate.add_argument("scenario")
    record = sub.add_parser("capture")
    record.add_argument("scenario")
    record.add_argument("--out", required=True)
    record.add_argument("--device", default="00008140-001039D01442801C")
    record.add_argument("--team", default="83S63575XD")
    record.add_argument("--side", choices=("native", "flutter", "both"), default="both")
    record.add_argument("--no-film", action="store_true")
    record.add_argument("--flutter", default="flutter")
    record.add_argument("--target", default="lib/lab/main.dart")
    record.add_argument("--native-scene", default="lab")
    record.add_argument("--leave-lab-installed", action="store_true")
    evaluate = sub.add_parser("compare")
    evaluate.add_argument("scenario")
    evaluate.add_argument("--native", required=True)
    evaluate.add_argument("--candidate", required=True)
    evaluate.add_argument("--out", required=True)
    evaluate.add_argument("--no-film", action="store_true")
    frames = sub.add_parser("extract")
    frames.add_argument("movie")
    frames.add_argument("--out", required=True)
    image = sub.add_parser("image")
    image.add_argument("scenario")
    image.add_argument("--native", required=True)
    image.add_argument("--candidate", required=True)
    image.add_argument("--out", required=True)
    fit = sub.add_parser("fit-spring")
    fit.add_argument("trace")
    fit.add_argument("--track", required=True)
    fit.add_argument("--property", required=True)
    fit.add_argument("--start", type=float, required=True)
    fit.add_argument("--end", type=float, required=True)
    fit.add_argument("--holdout")
    fit.add_argument("--out", required=True)
    matrix = sub.add_parser("matrix")
    matrix.add_argument("scenario")
    matrix.add_argument("--out", required=True)
    transfer = sub.add_parser("transfer")
    transfer.add_argument("scenario")
    for side in ("native", "candidate"):
        for background in ("black", "white"):
            transfer.add_argument(f"--{side}-{background}", required=True)
    transfer.add_argument("--out", required=True)
    args = parser.parse_args()
    try:
        if args.command == "fit-spring":
            result = fit_spring(read_rows(args.trace), args.track, args.property, args.start, args.end,
                                read_rows(args.holdout) if args.holdout else None)
            with Path(args.out).open("x") as handle:
                json.dump(result, handle, indent=2)
            print(json.dumps({k: v for k, v in result.items() if k != "samples"}, indent=2))
            return
        if args.command == "extract":
            data = extract(args.movie, args.out)
            print(json.dumps({k: v for k, v in data.items() if k != "frames"}, indent=2))
            return
        scenario = load(args.scenario)
        if args.command == "validate":
            print(f"VALID {scenario['id']} {digest(scenario)}")
        elif args.command == "matrix":
            out = Path(args.out)
            out.mkdir(parents=True, exist_ok=False)
            entries = []
            for appearance in ("light", "dark"):
                for name, background in (("black", {"kind": "solid", "color": "#000000"}), ("white", {"kind": "solid", "color": "#FFFFFF"}),
                                         ("grid", {"kind": "grid", "cell": 12}), ("ramp", {"kind": "ramp", "period": 120})):
                    variant = {**scenario, "id": f"{scenario['id']}-{appearance}-{name}", "appearance": appearance, "background": background}
                    path = out / (variant["id"] + ".json")
                    path.write_text(json.dumps(variant, indent=2) + "\n")
                    entries.append({"scenario": path.name, "sha256": digest(variant)})
            (out / "matrix.json").write_text(json.dumps(entries, indent=2))
            print(out)
        elif args.command == "capture":
            output = capture(scenario, args.out, args.device, args.team, args.side, not args.no_film, args.flutter,
                             not args.leave_lab_installed, args.target, args.native_scene)
            print(f"CAPTURED {output}")
        elif args.command == "image":
            result = compare_pair(args.native, args.candidate, scenario)
            path = Path(args.out)
            with path.open("x") as handle:
                json.dump(result, handle, indent=2)
            print(path)
        elif args.command == "transfer":
            result = compare_transfer(args.native_black, args.native_white, args.candidate_black, args.candidate_white, scenario)
            with Path(args.out).open("x") as handle:
                json.dump(result, handle, indent=2)
            print(args.out)
        elif args.command == "compare":
            native_dir, candidate_dir = Path(args.native), Path(args.candidate)
            native = read_rows(native_dir / "trace.jsonl")
            candidate = read_rows(candidate_dir / "trace.jsonl")
            result = compare(native, candidate, scenario)
            for side, directory in (("native", native_dir), ("candidate", candidate_dir)):
                path = directory / "capture-buffers.jsonl"
                if path.exists():
                    buffers = read_rows(path)
                    frames = [r for r in buffers if r.get("k") == "capture_buffer"]
                    result["quality"][side]["usbSource"] = {"cadence": cadence([r["pts"] for r in frames]),
                                                           "delegateDropCount": sum(r.get("k") == "capture_drop" for r in buffers),
                                                           "encoderDropCount": sum(r.get("k") == "capture_encode_drop" for r in buffers),
                                                           "movieAcceptedCount": sum(r.get("movieAccepted") is True for r in frames) if any("movieAccepted" in r for r in frames) else None,
                                                           "firstBuffer": frames[0] if frames else None,
                                                           "note": "delegate drops do not include upstream USB omissions or movie-output drops"}
                    if any("movieAccepted" in row for row in frames):
                        movie_index = directory / "frames/frames.json"
                        decoded = len(json.loads(movie_index.read_text())["frames"]) if movie_index.exists() else None
                        result["quality"][side]["usbSource"]["movieDecodedCount"] = decoded
                        if decoded != result["quality"][side]["usbSource"]["movieAcceptedCount"]:
                            result["failures"].append(f"{side} film: decoded frame count differs from accepted source buffers")
            has_films = (native_dir / "frames/frames.json").exists() and (candidate_dir / "frames/frames.json").exists()
            if has_films and not args.no_film:
                result["film"] = compare_films(native_dir / "frames", candidate_dir / "frames", native, candidate, scenario)
                result["failures"].extend(result["film"]["failures"])
            elif not args.no_film:
                result["failures"].append("film: paired recordings are missing")
            result["passed"] = not result["failures"]
            manifests = []
            for directory in (native_dir, candidate_dir):
                path = directory / "manifest.json"
                manifests.append(json.loads(path.read_text()) if path.exists() else None)
            page = write_report(result, scenario, args.out, *manifests)
            status = "PASS" if result["fidelityGatesDeclared"] else "EVIDENCE"
            print(f"{status if result['passed'] else 'REVIEW'} {page}")
            for failure in result["failures"]:
                print(f"  {failure}")
            if not result["passed"]:
                sys.exit(2)
    except (LabError, OSError, ValueError) as error:
        parser.exit(1, f"ERROR: {error}\n")
