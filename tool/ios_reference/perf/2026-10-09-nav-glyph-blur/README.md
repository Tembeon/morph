# Navigation glyph blur and decided fusion blocks (2026-10-09)

navigation_stage_bench reports (profile, Flutter 3.49.0-0.2.pre, three
shuffled repeats, 1500 ms windows). Summarize with
`python3 ../nav_quick/summ.py A.json B.json`.

- redmi-base-1/2: working baseline 37abe0e (flat only), two launches.
- redmi-comb / -comb-2: final source (glyph blur + decided fusion blocks).
- redmi-noraster / noblur / noop: attribution by removal (visual changes,
  not candidates): no Android glyph raster; also no item blur; also no
  partial item opacity.
- redmi-opt / redmi-cheap: final shader vs a one-tap stand-in (GPU cost of
  the blur shader).
- redmi-shots2: frozen-frame layer owners (`layer_owners`).
- moto-base-1, -120, -3: baseline launches (the -120 one asked for 120 Hz
  and still ran at 60). moto-new-1/2: final source.
- m120-base-1/2, m120-new-1/2: Moto at 120 Hz (system min_refresh_rate
  120 for the runs, restored to 60 after), A B B A.
- redmi-fusion-before/after.log.txt: per-call `FUSE <us> <shapes>` lines
  of flat container fusion during push/pop.

Analysis: ../../spec/glass-renderer.md "Navigation glyph blur in one pass".

Second round (Moto, 120 Hz via min_refresh_rate 120):
- f120-base-1 / f120-new-1/2: A B B with `cmd power
  set-fixed-performance-mode-enabled true` (steady, not maximal, clocks).
- h120-base-1 / h120-new-1: performance hints (NAV_HINTS) on both sides;
  worse than plain, not used as the reference.
- f120-lpush3: liquid push alone, three repeats (remounting the gallery);
  f120-lkeep: six pushes in one app (NAV_KEEP_APP). The first push after
  the idle start is twice as cheap per frame as every later one, in both.
- f120-llive.log.txt: live tickers every 250 ms after each action
  (NAV_TRACE_TICKERS): the bar motion clocks stop 1.25 - 1.5 s after the
  action (springs settling), then frames stop.
- moto-ticker-trace.log.txt: who requested frames 1 s into a window.
- moto-liquid-fusion-full / -decided.log.txt: `FUSE <us> <shapes> <field>`
  per liquid fusion with full evaluation vs decided blocks.
