Frost seed pass, policy exploration on the Pixel 6a (glass_audit_test.dart,
liquid, AUDIT_RUNS=5, AUDIT_GPUWORK=1, cooled to 38 C; GPU work traces moved
to /tmp/morph-perf/gpuwork, not committed). base = ec62123; cand = every
frosted layer outside a backdrop group blurs a seeded copy of its own
surroundings; lens = only layers up to 15000 lp2 of material (the lifted
knob and thumb). Launch order base, cand, lens, lens, cand, base (file
suffixes are launch slots). The landed state (an explicit flag on lifted
glass only) is perf/2026-10-06-pixel6a-frost-final.
