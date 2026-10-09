# 2026-10-10 navigation options evidence

Reports of `example/lib/perf/navigation_stage_bench.dart` run through
`../nav_quick/run.py` (Moto runs with `--gpu`: `*.gpuwork.txt.gz` +
`*.device.txt`, reduced by `../nav_quick/gpu.py`). Summaries in
`tool/audit/claude-navigation-options-report.md`.

| prefix | device | variants |
|---|---|---|
| `hlr-` | Redmi 6A flat | base 37abe0e / now 40a76ec / opt = now + MORPH_FLAT_SHADER_BODIES |
| `hlm-` | Moto g86 liquid | base 37abe0e / now 40a76ec / opt = now + MORPH_ANALYTIC_GEOMETRY (changes) |
| `hy-` | Moto liquid | a16606f: m = matte, a = analytic always, c = analytic changes |
| `edge-` | Moto liquid | e8916b9 scroll edge blur on / off |
| `sh-` | Moto liquid | 8c37f81 b = base, s = glass shadow paths kept |
| `fs-` | Moto flat | c48af2f o = off, n = MORPH_FLAT_SHADER_BODIES |
| `mf-` | Moto liquid | c48af2f b = base, f = fading glyphs through the shader |
| `rdf-` | Redmi flat | c48af2f c = base, f = fading glyphs through the shader |
| `rd-` | Redmi flat | c48af2f b = base, r = reduce-shader early-out (rejected) |

Example: `python3 ../nav_quick/compare.py base=hlr-base1.json,hlr-base2.json now=hlr-now1.json,hlr-now2.json opt=hlr-opt1.json,hlr-opt2.json`.
