# Round 4 resource study evidence

See tool/audit/codex-round4-resource-study.md for results and limitations.
Source 8cfcd219f494c349362cb6dda98d3f4d2e93ff15; original APK and raw trace
hashes in manifest.json. Production runtime is unchanged.

Baseline build with audit_android.sh:

- AUDIT_STEP=build, AUDIT_SOURCE=<archive of source>, AUDIT_TIERS="liquid flat"
- AUDIT_RUNS=3, AUDIT_APPS=<temporary APK directory>
- AUDIT_DEFINES="--dart-define=AUDIT_SCENES=tab-bar,controls,menu,sheet
  --dart-define=AUDIT_SHOTS=false --dart-define=AUDIT_CENSUS=true
  --dart-define=AUDIT_CENSUS_OWNERS=true"

Energy order "liquid flat flat liquid", ENERGY_COOL_C=37. The four traces
included the orphan recorder described in the report: exploratory data,
not a candidate acceptance run. energy.py caches rail/scheduler reductions.
verify_raster.py independently joins sched to all app raster thread names;
verification.txt confirms agreement for every retained energy launch.
Current caches were regenerated with raster_threads_aggregated=true.

Separate baseline GPU runs: AUDIT_STEP=run, AUDIT_GPUWORK=1,
AUDIT_COOL_C=37, AUDIT_LABEL=round4-baseline-gpu. Liquid was repeated after
an interrupted first capture; rejected-gpu.json retains its disposition.
gpu-coverage.json validates the accepted traces. reduce_gpu.py from the
round3-controls-profile evidence produced the per-window and weighted
GPU summaries. Original traces are intentionally temporary.

Diagnostic clone: apply diagnostic.patch to the source archive with git apply --unidiff-zero. The patch
passed git apply --check --unidiff-zero. It is study-only and is not production code.

- Counters: same four scenes, three repeats, MORPH_RESOURCE_STUDY=true,
  census/owners on, screenshots off; APK liquid-study.
- VM heap probe: counters off, MORPH_ALLOC_STUDY=true, two repeats,
  census on, screenshots off; APKs liquid-alloc and flat-alloc.
- Native: counters/VM probing off, two repeats, TraceSystrace metadata
  true. The native APK was built before the bounds/VM-probe additions;
  all existing counter branches were compile-time false. trace_android.sh,
  then atrace_slices.py for per-scene/per-thread reductions. Native report
  and raw SHA are retained.

reduce_study.py reads original diagnostic reports. Heap-probe reports were
then reduced: original allocation_study members are omitted; their counts,
accumulator/current equality, reset timestamp and memoryUsage remain in
allocation_probe_reduction. study-summary.json retains top-class values.
Raw report hashes are in manifest.json. These are heap snapshots; do not
interpret the reported accumulators as allocation rates or the retained
probe's heap growth as a production leak.

reduce_gc.py joins young GC and UI BeginFrame intervals on the atrace
clock. The native summaries include whole scene windows; BeginFrame self,
inclusive wall time and scheduled running CPU are distinct measurements.

Tool verification: mock-adb and mock-sleep were placed in a temporary
PATH and energy_android.sh was run with MOCK_ADB_LOG. A deliberately failed
am start exits 1 and the EXIT trap calls kill -TERM only for recorder 4321.
cleanup-calls.jsonl and cleanup-verification.txt retain the result. No
real device is touched by that fault-injection run. legacy-cache-check.txt
confirms old cached CPU data is flagged without changing rail/frame data.

Validation logs retain zero-issue analysis, final package/example test
counts, zero-warning dartdoc and the diagnostic clone's analysis. The
release gallery was restored in portrait using the runtime unchanged
round-3 release APK; its hash and restoration result are retained.
