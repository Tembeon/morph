# Navigation research reference notes

Reviewed 2026-10-09. External code is study material, not a Pixel benchmark.
No implementation code or physics constants were copied into Morph.
Raw responses and reviewed source files are archived with the experiment.

## Pinned navigation shell reference

`sdegenaar/liquid_glass_widgets`, MIT, commit
`7437a8acb56bae51d6969e3b9f51b257d461d047`:

- [Navigation transition notes](https://github.com/sdegenaar/liquid_glass_widgets/blob/7437a8acb56bae51d6969e3b9f51b257d461d047/docs/GLASS_NAVIGATION_TRANSITION.md)
- [Morph engine notes](https://github.com/sdegenaar/liquid_glass_widgets/blob/7437a8acb56bae51d6969e3b9f51b257d461d047/docs/LIQUID_MORPH_ENGINE.md)
- `glass_navigation_shell.dart`, `glass_pinned_bar_chrome.dart`,
  `shared/glass_nav_pinned_host.dart`, `glass_morph_controller.dart`
  in the pinned `lib/` tree.

The source keeps chrome above Navigator and registers route descriptors.
Hidden sizing content preserves measured layout without making a second
visible shell. Foreground blur/fade is distinct from glass, including a
special path when an item itself owns glass. This corroborates ownership
and content/material separation as useful design principles. Morph already
has those main divisions. It does not establish a faster blur or a need
to replace Morph's measured motion with that project's profiles.

## Pinned owned-source renderer reference

`medfa12/liquid-glass-react`, MIT, commit
`a7d3c5ebd04b7efdf264a901cc521f77878744d1`:

- [README and source](https://github.com/medfa12/liquid-glass-react/tree/a7d3c5ebd04b7efdf264a901cc521f77878744d1)
- `src/container.ts` groups nearby rectangles and chunks groups into draws.
- `src/renderer.ts` owns a supplied background texture and regenerates its
  mipmaps when it uploads an updated source.

The transferable ideas are component grouping and independent texture
invalidation. The README explicitly requires an image/canvas/video source;
WebGL cannot directly sample arbitrary live DOM pixels. This does not solve
acquisition of arbitrary Flutter route pixels or prove Apple's algorithm.
Mipmapped sampling is a different quality/performance contract from exact
stock Gaussian and needs the existing native ownership/cadence checks.

## Native contest account

[James Randolph's primary account](https://jamesrandolph.me/tg-contest-2025)
describes rejecting per-frame hierarchy snapshot/Metal work and using
platform layer filtering for a metaball-style mask. It is evidence about
that author's implementation, not a portable Flutter API or a measured
Pixel saving. Mask formation, backdrop filtering and colored foreground
content remain separate responsibilities. The private Core Animation
filter path is not proposed as a package dependency.

## Flutter lifecycle and scope

The current source and stable crash experiment are documented in
`tool/audit/codex-gpu-pass-lifecycle-report.md`. The relevant primary issue
discussions are [#193867](https://github.com/flutter/flutter/issues/193867),
[#193804](https://github.com/flutter/flutter/issues/193804), and
[#188474](https://github.com/flutter/flutter/issues/188474).
Creating a fresh command buffer for each pass, as the examined example
does, is not a multi-pass-in-one-buffer demonstration. Combining draws
inside one supported pass remains a different optimization.

The Apple API links and `anuero/LiquidGlass` in the user brief are useful
additional references but were not independently re-reviewed in this
round. Their claims are not used to admit this experiment. The brief's
reported prior numerical results are checked against local audit reports,
not treated as new measurements from an external author.
