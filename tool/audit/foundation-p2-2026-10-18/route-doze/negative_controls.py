import subprocess
import sys
from pathlib import Path

EXAMPLE = Path(__file__).resolve().parents[4] / "example"
TESTS = ["test/proto/menu_route_replay_test.dart", "test/proto/menu_route_doze_test.dart"]
MUTATIONS = [
    ("hand-back anchor 8 ms early", "lib/proto/menu_route_probe.dart",
     "        to: source,\n        toTime: anchor,", "        to: source,\n        toTime: anchor - 0.008,"),
    ("commands without the model-time floor", "lib/proto/menu_transfer_probe.dart",
     "math.max(localTime + _offset, _motion.time)", "localTime + _offset"),
    ("close on the last sampled time", "lib/proto/menu_route_probe.dart",
     "final time = _clock.resumeAt(_session.now());\n      _session.command(() => _session.transfer.close(_lease, time));",
     "_clock.resumeAt(_session.now());\n      _session.command(() => _session.transfer.close(_lease, _clock.time));"),
]


def main():
    failed_to_fail = 0
    for name, relative, old, new in MUTATIONS:
        path = EXAMPLE / relative
        original = path.read_text()
        if original.count(old) != 1:
            sys.exit(f"{name}: mutation target not found once in {relative}")
        try:
            path.write_text(original.replace(old, new))
            result = subprocess.run(["flutter", "test", "--no-pub", "-j", "5", *TESTS], cwd=EXAMPLE, capture_output=True, text=True)
        finally:
            path.write_text(original)
        summary = next((line for line in reversed(result.stdout.splitlines()) if "tests passed" in line or "tests failed" in line), "no summary")
        failures = sorted({line.split(": ", 1)[1].removesuffix(" [E]") for line in result.stdout.splitlines() if line.endswith("[E]")})
        print(f"## {name}\nexit {result.returncode}; {summary}")
        for failure in failures:
            print(f"- {failure}")
        if result.returncode == 0:
            failed_to_fail += 1
    sys.exit(1 if failed_to_fail else 0)


if __name__ == "__main__":
    main()
