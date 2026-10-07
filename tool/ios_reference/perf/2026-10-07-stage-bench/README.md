# Stage stand smoke evidence

See `tool/audit/codex-stage-bench-report.md` for the protocol and limits.
Default: seven cases, three repeats, 2400 ms windows, GPU tracing.
Matrix: 36 text/motion/grouping cases, one repeat, 600 ms windows, GPU.
Large: five static-backdrop cases, two repeats, 600 ms windows, no trace.
Energy: separate default launch; existing Perfetto reducer cache and notes.
These verify the measurement tools, not an optimization or weak-phone target.

Recompute frame/GPU summaries from the repository root:

```sh
python3 tool/ios_reference/perf/stage_bench/summarize.py tool/ios_reference/perf/2026-10-07-stage-bench/default/stage-1.json --out /tmp/morph-stage-default
python3 tool/ios_reference/perf/stage_bench/summarize.py tool/ios_reference/perf/2026-10-07-stage-bench/matrix/matrix-1.json --out /tmp/morph-stage-matrix
python3 tool/ios_reference/perf/stage_bench/summarize.py tool/ios_reference/perf/2026-10-07-stage-bench/large/large-1.json --out /tmp/morph-stage-large
```

`.gpuwork.txt.gz` contains filtered native events. The selection preserves
every relevant app period and frequency transition; its reduction was
checked identical to the original trace. `evidence.json` records the hashes.
Reports retain every frame. Build records identify flags, APK/source hashes
and production HEAD. The final build also corrects even-count medians.

With the existing perfetto Python dependency, energy.py can reprint the
cached reduction from `energy/`. The raw 24 MB Perfetto trace is omitted;
its hash is retained in `energy/evidence.json`. Recomputing those counters
independently requires a new trace. One launch's whole-phone power cannot
rank these modes. Initial energy notes contain full thermalservice output;
the reducer's compact skin array is empty for this early launch. Later
runner versions also emit the compatible `skin:` fields.

`restoration.json` records the original gallery checksum and device cleanup.
No APK, new Python dependency, runtime optimizer or pixel-parity claim is
part of this evidence.
