ADPF (Android Performance Hint API) on the Pixel 6a, energy and frames,
2026-10-06, base 6cdd2f3 plus example/lib/perf/adpf.dart and the audit's
ADPF / AUDIT_IDLE_S options (this branch). Verdict: REJECTED (frames gain,
energy rises on the menu and the sheet). glass-renderer.md "Energy: ADPF
and the fusion workers" on wip/measured-liquid-glass carries the tables.

Variants (profile, liquid, AUDIT_RUNS=5, AUDIT_SHOTS=false,
AUDIT_IDLE_S=60): off; on (ADPF=true: one hint session for the UI thread,
one for 1.raster, target 16.67 ms, every FrameTiming's build and raster
duration reported); eff (on + ADPF_EFFICIENT=true:
setPreferPowerEfficiency on both sessions). Launch order off on eff eff on
off off on eff eff on off; each from a skin below 37 C; phone on AC, full,
not charging (status 4, level 100). energy_android.sh / energy.py; the
traces (100 MB each) are not kept, energy.py reprints from the
<run>.energy.json files. summary.txt is energy.py's output.

The device's hint service during an `on` launch (dumpsys performance_hint):
two tag-4 sessions, TIDs [main] and [1.raster], 16666667 ns; HWUI's own
tag-2 session [main, RenderThread, 2 hwui workers] exists with or without.
