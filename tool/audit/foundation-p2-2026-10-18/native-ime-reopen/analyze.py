import argparse
import json
import math
from pathlib import Path
import shutil
import sys

PHASES = ["before", "after", "closed", "reopened", "closedAgain"]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def delta(first, second):
    for value in [first, second]:
        require(isinstance(value, list) and len(value) == 4, "invalid frame shape")
        require(all(isinstance(x, (float, int)) and math.isfinite(x) for x in value), "nonfinite frame")
        require(value[2] > 0 and value[3] > 0, "empty frame")
    return max(abs(a - b) for a, b in zip(first, second))


def collect(attachments, directory):
    expected = {f"keyboard-{mode}-geometry": ".json" for mode in ["none", "show", "hide"]}
    expected.update({f"{mode}-{phase}": ".png" for mode in ["none", "show", "hide"] for phase in PHASES + (["typed"] if mode == "show" else [])})
    found = set()
    for test in json.loads((attachments / "manifest.json").read_text()):
        if "testKeyboardSelectionReopen" not in test["testIdentifier"]:
            continue
        for item in test["attachments"]:
            name = item["suggestedHumanReadableName"].split("_0_")[0]
            if name not in expected:
                continue
            require(name not in found, "duplicate named attachment")
            source = attachments / item["exportedFileName"]
            require(source.parent == attachments and source.is_file(), "invalid attachment path")
            target = directory / (name + expected[name])
            require(not target.exists() or source.read_bytes() == target.read_bytes(), "refusing different replacement attachment")
            shutil.copyfile(source, target)
            found.add(name)
    require(found == set(expected), "missing named selection attachments")


def analyze(directory):
    receipt = json.loads((directory / "commands.json").read_text())
    require(receipt["test"] == "selection", "wrong test flow")
    statuses = {item["name"]: item["exitCode"] for item in receipt["commands"]}
    require(all(statuses.get(name) == 0 for name in ["test", "export", "copy-none", "copy-show", "copy-hide"]), "native test or artifact collection failed")
    modes = {}
    for mode in ["none", "show", "hide"]:
        geometry = json.loads((directory / f"keyboard-{mode}-geometry.json").read_text())
        events = json.loads((directory / f"events-{mode}.json").read_text())
        require(geometry["mode"] == mode and geometry["flow"] == "selectionReopen" and geometry["rowCount"] == 10, "wrong geometry flow")
        require(events and all(event["mode"] == mode and event["rowCount"] == 10 for event in events), "wrong event mode or row count")
        samples = geometry["samples"]
        expected = PHASES + (["typed"] if mode == "show" else [])
        require([sample["phase"] for sample in samples] == expected, "wrong snapshot phases")
        titles = ["Native first", "Native second", "Native third", "Native row 10"]
        for index, sample in enumerate(samples):
            require([row["title"] for row in sample["rows"]] == titles, "wrong observed row set")
            require(math.isfinite(sample["startTime"]) and math.isfinite(sample["endTime"]) and sample["startTime"] <= sample["endTime"], "invalid snapshot interval")
            if index:
                require(samples[index-1]["endTime"] < sample["startTime"], "snapshot intervals overlap")
        require(all(math.isfinite(event["time"]) for event in events), "nonfinite event time")
        require(all(first["time"] <= last["time"] for first, last in zip(events, events[1:])), "event journal is not ordered")
        tokens = {event["sourceToken"] for event in events}
        require(len(tokens) == 1 and all(isinstance(token, str) and token for token in tokens), "source identity changed")
        triggers = [event for event in events if event["kind"] == "menuTriggered"]
        actions = [event for event in events if event["kind"] == "selected"]
        require(len(triggers) == 2 and [event["presentation"] for event in triggers] == [1, 2], "wrong presentation count")
        require(len(actions) == 2 and [event["title"] for event in actions] == ["Native first", "Native second"], "wrong selection callbacks")
        require([event["presentation"] for event in actions] == [1, 2] and [event["selectionCount"] for event in actions] == [1, 2], "callback counters mismatch")
        before, after, closed, reopened, closed_again = samples[:5]
        require(triggers[0]["time"] < before["startTime"], "before snapshot precedes opening")
        require(after["endTime"] < actions[0]["time"] < closed["startTime"], "first callback outside selection window")
        require(closed["endTime"] < triggers[1]["time"] < reopened["startTime"], "reopen outside snapshot window")
        require(reopened["endTime"] < actions[1]["time"] < closed_again["startTime"], "second callback outside selection window")
        begins = [event for event in events if event["kind"] == "keyboardCommandBegin"]
        if mode == "none":
            require(not begins and not before["keyboardExists"] and not after["keyboardExists"], "bad control keyboard state")
        else:
            require(len(begins) == 1 and before["endTime"] < begins[0]["time"], "keyboard command overlaps before snapshot")
            command = [event for event in events if event["kind"] == "keyboardCommand"]
            require(len(command) == 1 and command[0]["accepted"] is True, "responder command refused")
            kind = "UIKeyboardDidShowNotification" if mode == "show" else "UIKeyboardDidHideNotification"
            require(any(event["kind"] == kind and begins[0]["time"] < event["time"] < after["startTime"] for event in events), "keyboard transition incomplete")
            require(before["keyboardExists"] == (mode == "hide") and after["keyboardExists"] == (mode == "show"), "keyboard transition missing")
        for sample, count in [(closed, 1), (closed_again, 2)]:
            require(all(not row["exists"] and row["frame"] is None for row in sample["rows"]), "menu still present after selection")
            require(sample["sourceHittable"] is True and sample["selectionCount"] == str(count), "closed source unavailable or counter mismatch")
        for sample in [before, after, reopened]:
            require(all(row["exists"] for row in sample["rows"]), "observed rows missing in open menu")
        active_delta = max(delta(first["frame"], last["frame"]) for first, last in zip(before["rows"], after["rows"]))
        source_delta = max(delta(before["source"], sample["source"]) for sample in samples)
        typed = None
        if mode == "show":
            typed = samples[-1]["editorValue"]
            edits = [event for event in events if event["kind"] == "editorChanged"]
            require(isinstance(typed, str) and typed.lower() == "native" and edits and edits[-1]["text"].lower() == "native", "focus typing was not received")
            require(all(event["fieldFocused"] is True for event in edits), "editor typing without first-responder observation")
            require(closed_again["endTime"] < edits[0]["time"] <= edits[-1]["time"] < samples[-1]["startTime"], "typing outside declared window")
        modes[mode] = {"callbacks": [event["title"] for event in actions], "presentations": len(triggers),
                       "sourceToken": next(iter(tokens)), "sourceMaxDeltaPt": source_delta, "activeRowMaxDeltaPt": active_delta,
                       "firstRowAfterTransitionY": after["rows"][0]["frame"][1], "firstRowReopenedY": reopened["rows"][0]["frame"][1],
                       "reopenFirstRowShiftPt": reopened["rows"][0]["frame"][1] - after["rows"][0]["frame"][1],
                       "keyboardByPhase": {sample["phase"]: sample["keyboardExists"] for sample in samples},
                       "focusAtActions": [event["fieldFocused"] for event in actions], "focusAtReopen": triggers[1]["fieldFocused"],
                       "closedSourceHittable": True, "typedValueWithoutEditorTap": typed}
    return {"modes": modes, "claim": "functional selection/closed source/reopen/focus only; no optical morph landing or transient motion proof"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--collect", type=Path)
    args = parser.parse_args()
    try:
        receipt = json.loads((args.directory / "commands.json").read_text())
        require(any(item["name"] == "test" and item["exitCode"] == 0 for item in receipt["commands"]), "native test was not successful")
        if args.collect:
            collect(args.collect, args.directory)
        result = analyze(args.directory)
        (args.directory / "analysis.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2))
    except (KeyError, TypeError, ValueError, OSError) as error:
        print(f"INVALID EVIDENCE: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
