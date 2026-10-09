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
