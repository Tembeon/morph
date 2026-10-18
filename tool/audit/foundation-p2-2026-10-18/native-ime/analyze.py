import argparse
import json
import math
from pathlib import Path
import shutil
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def frame(value):
    require(isinstance(value, list) and len(value) == 4, "invalid frame shape")
    require(all(isinstance(x, (int, float)) and math.isfinite(x) for x in value), "nonfinite frame")
    require(value[2] > 0 and value[3] > 0, "empty frame")
    return value


def delta(first, second):
    return max(abs(a - b) for a, b in zip(frame(first), frame(second)))


def collect(attachments, output):
    expected = {f"keyboard-{mode}-geometry": ".json" for mode in ["none", "show", "hide"]}
    expected.update({f"{mode}-{phase}": ".png" for mode in ["none", "show", "hide"] for phase in ["before", "after"]})
    found = set()
    for test in json.loads((attachments / "manifest.json").read_text()):
        for item in test["attachments"]:
            name = item["suggestedHumanReadableName"].split("_0_")[0]
            if name not in expected:
                continue
            require(name not in found, "duplicate named probe attachment")
            source = attachments / item["exportedFileName"]
            require(source.parent == attachments and source.is_file(), "invalid attachment path")
            target = output / (name + expected[name])
            require(not target.exists() or target.read_bytes() == source.read_bytes(), "refusing to replace a different attachment")
            shutil.copyfile(source, target)
            found.add(name)
    require(found == set(expected), "missing or duplicate named probe attachments")


def analyze(directory):
    modes = {}
    before_frames = {}
    for mode in ["none", "show", "hide"]:
        geometry = json.loads((directory / f"keyboard-{mode}-geometry.json").read_text())
        events = json.loads((directory / f"events-{mode}.json").read_text())
        require(geometry["mode"] == mode, "mode mismatch")
        require(len(geometry["samples"]) == 2, "expected before/after snapshots")
        before, after = geometry["samples"]
        require(before["phase"] == "before" and after["phase"] == "after", "wrong phases")
        require(all(math.isfinite(sample[key]) for sample in [before, after] for key in ["startTime", "endTime"]), "nonfinite snapshot time")
        require(before["startTime"] <= before["endTime"] < after["startTime"] <= after["endTime"], "snapshot intervals overlap")
        commands = [event for event in events if event["kind"] == "keyboardCommandBegin"]
        command_gap = None
        settled_gap = None
        if mode == "none":
            require(not commands and not before["keyboardExists"] and not after["keyboardExists"], "invalid no-keyboard control")
        else:
            require(len(commands) == 1, "missing or repeated keyboard command")
            accepted = [event for event in events if event["kind"] == "keyboardCommand"]
            require(len(accepted) == 1 and accepted[0]["accepted"] is True, "responder command was not accepted")
            completion = "UIKeyboardDidShowNotification" if mode == "show" else "UIKeyboardDidHideNotification"
            transitions = [event for event in events if event["kind"] == completion and event["time"] > commands[0]["time"]]
            require(len(transitions) == 1, "missing completed keyboard transition")
            command_gap = commands[0]["time"] - before["endTime"]
            settled_gap = after["startTime"] - transitions[0]["time"]
            require(command_gap > 0, f"{mode}: before snapshot overlaps keyboard command")
            require(settled_gap > 0, f"{mode}: after snapshot precedes keyboard completion")
            require(before["keyboardExists"] == (mode == "hide") and after["keyboardExists"] == (mode == "show"), "keyboard visibility did not change as declared")
        require([row["title"] for row in before["rows"]] == [row["title"] for row in after["rows"]], "row identity mismatch")
        row_deltas = {}
        for first, last in zip(before["rows"], after["rows"]):
            row_deltas[first["title"]] = delta(first["frame"], last["frame"]) if first["exists"] and last["exists"] else None
        all_present = all(value is not None for value in row_deltas.values())
        maximum = max(row_deltas.values()) if all_present else None
        source_delta = delta(before["source"], after["source"])
        occluded = None
        if mode == "show":
            keyboard = next(event["keyboardEnd"] for event in events if event["kind"] == "UIKeyboardDidShowNotification")
            frame(keyboard)
            bottoms = [frame(row["frame"])[1] + row["frame"][3] for row in after["rows"] if row["exists"]]
            occluded = max(0, max(bottoms) - keyboard[1]) if bottoms else None
        before_frames[mode] = before
        modes[mode] = {"rowCount": geometry.get("rowCount", 3), "allObservedRowsRemain": all_present,
                       "rowDeltasPt": row_deltas, "maxRowDeltaPt": maximum, "sourceDeltaPt": source_delta,
                       "rowsStableWithin1Pt": all_present and maximum <= 1,
                       "beforeToCommandGapSeconds": command_gap, "completionToAfterGapSeconds": settled_gap,
                       "observedRowBottomBeyondKeyboardTopPt": occluded,
                       "keyboardBefore": before["keyboardExists"], "keyboardAfter": after["keyboardExists"]}
    control = before_frames["none"]
    hidden = before_frames["hide"]
    require(control["source"] == hidden["source"], "cannot compare initial placement for different sources")
    first = control["rows"][0]
    second = hidden["rows"][0]
    placement_shift = second["frame"][1] - first["frame"][1] if first["exists"] and second["exists"] else None
    return {"modes": modes, "initialFirstRowShiftWithKeyboardPt": placement_shift,
            "claim": "endpoint row geometry only; no transient motion, body pixel equivalence, context-menu, or Flutter parity claim"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--collect", type=Path)
    args = parser.parse_args()
    try:
        if args.collect:
            collect(args.collect, args.directory)
        result = analyze(args.directory)
        (args.directory / "analysis.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2))
    except (ValueError, KeyError, OSError) as error:
        print(f"INVALID EVIDENCE: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
