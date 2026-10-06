Energy of the menu fusion workers on the Pixel 6a (Mali-G78, Vulkan, 60 Hz),
2026-10-06, base 6cdd2f3 (a worktree; the harness options of this commit
copied in). energy_android.sh: the glass audit's menu scene alone
(AUDIT_SCENES=menu, AUDIT_RUNS=10: the rich menu opened and closed twice per
run, 40 transitions a launch), liquid tier, no shots, profile, every launch
under a Perfetto trace of the ODPM power rails (100 ms), cpufreq, cpuidle
and sched (energy_android.cfg), each from a skin below 37 C. Phone on AC,
battery full and not charging (status 4, level 100) for every launch; the
rails measure the PMIC outputs either way. Traces (100 MB each) are not
kept; energy.py reprints from the per-launch <run>.energy.json.

fusion-ab: FUSION_PREFETCH=false (fzoff) and true (fzon, the shipping
default: three predicted frames fused per fusing frame), ABBA x2.
fusion-predictions: the same two plus fz1 (MorphMenuFusion.prefetchFrames
= 1, a local build, not committed), launch order fz1 fzon fzoff fzoff fzon
fz1 fz1 fzon fzoff.

Menu scene, medians (mJ over the 45 s window; frames are the report's
medians over runs, ms):

| run | variant | total mJ | CPU rails mJ | worker CPU s | UI thread CPU s | build p95 | raster p95 | over budget | served / fused here |
|---|---|---|---|---|---|---|---|---|---|
| ab | off | 34063 | 7749 | 1.3 | 20.5 | 17.23 | 16.34 | 20 | 0 / 1024 |
| ab | on (3 ahead) | 36098 (+6.0 %) | 9029 | 13.4 | 20.4 | 14.66 | 15.10 | 15 | 640 / 441 |
| pred | off | 34241 | 7923 | 1.2 | 20.7 | 16.14 | 16.22 | 18 | 0 / 1046 |
| pred | on (3 ahead) | 35789 (+4.5 %) | 8706 | 13.5 | 20.4 | 15.17 | 15.25 | 15 | 597 / 483 |
| pred | 1 ahead | 33957 (-0.8 %) | 7707 | 5.4 | 20.6 | 17.52 | 15.82 | 18 | 457 / 557 |

Launch spread within a variant: 0.8 - 2.1 percent of the total. Worker CPU
is the app's DartWorker threads (the isolate pool; fzoff's 1.2 - 1.3 s is
GC and the rest of the pool).
