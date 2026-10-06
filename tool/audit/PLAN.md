# morph - plan after the 2026-10-03 campaign

Handoff for future sessions. Read this first, then CLAUDE.md, then the
passport of whatever you touch (tool/ios_reference/spec/). The audit
behind most items is tool/audit/2026-10-03-audit.md (finding IDs E1, B1,
C1, G1, ... refer to it).

## Where things stand (2026-10-03, late)

- Branch `wip/measured-liquid-glass`, pushed to origin as a BACKUP only.
  Not merged, not tagged, Pages untouched (Pages builds from main).
  Owner's call: no release before performance, tech debt and the audit
  fixes are done.
- 0.7.0 content on the branch: the measured widget layer (iOS 27 Liquid
  Glass copy), the glass renderer INSIDE the package (MorphGlassRenderer,
  tiers flat/frosted/liquid, MorphAdaptiveGlass, the package outline is
  the shape truth), spec passports + reference keeper workflow, disabled
  looks and light material measured and ported, menu fusion (blurred-SDF
  neck), context menu dim (engine scrimMotion seam), push zoom, sheet
  zoom scrub, date picker month/year wheels, search/date/alert polish.
- Last green check (agent reports): analyze 0, 816 package tests,
  11 example tests, dart doc 0 warnings, iOS/macOS/web builds, macOS
  autodemo `AUTODEMO done` with no EXCEPTION.
- MENU API PORT LANDED (4f810d3, 065e0f4): sealed MorphMenuEntry
  (item, section, submenu, divider, deferred, free-form MorphMenuWidget),
  measured layout, submenus as stacked cards, live resize, deferred
  loading row, keyboard/a11y/RTL; declarative updates (no controller).
  The whole-stack close IS the ordinary menu close (settled on data).
  Leftovers: root list 0.97 shrink not drawn, unmeasured values (card
  platter colours, maxTitleLines heights, cell/palette radii), cards
  taller than the cap cut instead of scrolled, the bar back menu ignores
  entry changes while open, no dark-mode simulator pass, audit M2 (close
  the motion on dispose - hit a locked-tree assert) still open.


## Status 2026-10-04 early morning (owner asleep)

- Audit waves 1-2 landed: WP-B (45fd91d, 6e32d80, 78a8aee), WP-C (da7e6db..4e8df30), WP-A (5f4ab8e), WP-I (ffc0c1e + device fix f8b921d), WP-D (fa0df3c), WP-G (d84e125). A, I, D, G were written by Codex (gpt-6.1-sol) in a sandbox that cannot run flutter test; the coordinator verified the combined tree (966 + 11 tests, analyze 0, doc 0, iOS/web/macOS builds, autodemo).
- Submenu calibration by film landed (42b53f7..0cc68ff).
- CHANGELOG lines of all of the above wait in tool/audit/CHANGELOG-pending.md (merge into CHANGELOG.md 0.7.0, then delete the file).
- LESSON: WP-I's shader packaging silently fell back to frosted on the device (the build hook never gets data assets on Flutter 3.47.2). Fixed in f8b921d. The fallback diagnostic prints only in debug - make a liquid->frosted fallback observable in release (an onFallback callback or a one-time FlutterError.reportError), and always verify renderer changes on the device (glass_audit now records liquid_available).
- WP-F (2ecf687; travel spring 0.401/0.856 confirmed by the replays, passports fixed) and WP-J (76cc9ab; CHANGELOG-pending merged and deleted) landed. Tree: 985 + 11 tests, analyze 0, doc 0, iOS + web build.
- Wave 3 landed: WP-H control host (cfce3b1), D5 menu host merge + WP-E rest (793dc9f). Tree: 1014 + 11 tests, analyze 0, doc 0, iOS/web/macOS builds, autodemo clean. The audit is DONE except PF9 (edge effect backdrop grouping, visual change) and P5api (configurable bar-menu tuning).
- Next: make a liquid->frosted fallback observable in release; owner decision A8 (engine flights clamp size past value 1, UIKit overshoots size), then the performance passport.

## Status 2026-10-04 evening

- A8 (5482cb1) and FB/P5api (be14e67) committed after a full serial check: 1057 + 14 tests, analyze 0, doc 0. Not pushed, not on the phone.
- Codex built the shared native/Flutter measurement LABORATORY (tool/ios_reference/lab, 740ed11..da224dd) and fixed submenu bounds/material/scrolling (51d0983..6bbd948). Its handoff is tool/ios_reference/lab/HANDOFF-20261004.md - read it before menu work.
- Still uncommitted: the submenu card material retention + measured light shadow (menu.dart, menu_motion.dart, glass.dart shadows, two fixtures). Tests green, but the missing attached rim on the More card is NOT solved; the leading hypothesis is GPU blending over the renderer's data textures (unproven).
- lab/out holds ~14 GB of captures (ignored). A Mac reboot happened during a profile build on 2026-10-04; run one heavy job at a time.

## Status 2026-10-05 morning (owner asleep overnight, agents autonomous)

- Menu: the lab's missing rim was a painter-scope bug (MorphGlass below the Navigator), not the renderer (db97e2c); card material + measured shadow (7529798); close and open timing fitted to device data (c4d14a7, e57255f). Residuals in spec/menu-api.md: late-close 7-8 pt width gap (suspected touch-vs-frame clock offset, needs measuring), root rows dimming under the card, kept-card outline.
- Glass carried into overlays: widget surfaces (5517a41) and engine flights via inherited themes (43fe4d6). Owner decision: the engine may depend on widgets; widget quality first.
- Gallery runs on MorphNavigationStack + new MorphListSection/MorphListRow (spec/lists.md) (5cca0fd..dab5376); presentation boundary so menus/sheets open above stack bars, bar button tap-to-open menu measured (97ef356..ca0268a).
- Performance: research tool/audit/perf-research-2026-10-05.md + perf-opinion-fable.md; phase 1 (c3cd90f..94d7f12) and phase 2 (2fc1dbe..7b94960). Device harness tool/ios_reference/perf/audit.sh, counters test/perf_counts_test.dart. Identical-output fixes cut UI work; controls build p95 down ~0.7 ms; raster unchanged (liquid ~3x flat: captures + blurs).
- OWNER DECISIONS PENDING (pixel-changing perf levers): menu silhouette analytic union / single-box card (menu p95 2.5-3.8 ms per frame), edge effects in the bars' capture, glass shadows without per-surface saveLayer, governor stepping liquid->frosted makes controls MORE expensive (frosted raster p95 3.65 vs liquid 2.88).
- Being checked: a possible shared-backdrop staleness bug (Impeller snapshots the shared group at the first filter in paint order).

## Status 2026-10-05 early (clock + overlay backdrop agent)

- Clock (493f012, c120e87, de82e39; spec/README.md "Clocks"): touch vs
  frame clock bases measured; MorphClock now stamps the event's own
  touch time stamp (the reference of every fitted delay and replay; the
  old delivery anchor started reactions ~15 - 25 ms late). The menu
  late-close residual is NOT re-measured: the XCUITest runner timed out
  enabling automation mode on the phone (needs the owner at the phone:
  unlock, check Settings > Developer > Enable UI Automation, then rerun
  lab.py capture menu-return.json with film; the lab now logs lab_stamp).
- Backdrop groups (8acf447): context menu hero/satellites and frosted
  lenses fixed on device. OWNER DECISION: two resting body glass with
  content painted between them still read a stale root copy (72 / 43 max
  diff); a group per body glass control fixes it at a capture each.

## Status 2026-10-05 (perf levers agent, owner decisions of the day)

- Governor (6f8a325): steps liquid -> flat; frosted only via
  `MorphGlassTierPolicy.tiers`. Plain unions exact (f9293cd): the menu's
  r < 1 tail and submenu cards no longer trace a field (menu build p95
  liquid 2.34 -> 1.87, frosted 3.41 -> 1.91). Glass shadows clipped, no
  saveLayer (b0f79b1): liquid raster p95 -0.2 .. -0.5 on every scene
  with shadowed glass. Numbers and shots in spec/glass-renderer.md.
- Edge effects in the bars' group: measured, visible (capsules lose the
  edge effect's fade), NOT adopted.
- Second resting body glass: not detectable per frame; options A - D with
  device costs in glass-renderer.md - OWNER DECISION still open.

## Status 2026-10-06 evening - HANDOFF (optimization campaign)

Branch wip/measured-liquid-glass, pushed as a backup (HEAD 5950daa + this). All checks green at handoff: 1397 package + 17 example tests, analyze 0, dart doc 0. Not merged, not tagged.

What landed 2026-10-05/06 (details: CLAUDE.md glass seam + Performance passport, tool/ios_reference/spec/glass-renderer.md perf sections, tool/audit/*.md):
- Tiers: liquid / fake (fallback, web) / flat (cheap tier on GLES + pre-A13). Frosted and the frame-time governor removed. Tier chosen once per session.
- Startup: pipeline warm-up in precache (first glass frame 100+ ms -> 5 ms), 1 s precache budget, Metal command-queue hang fixed, GLES warm-up crash fixed.
- Renderer: Vulkan gray box (Mali ternary miscompile) fixed; uniform arena (no 31-render cap); 32 shapes per layer; F7 one color-model family per program (back to full Mali occupancy); shader audit batch (harness: example/integration_test/shader_parity_test.dart, tool/audit/shader/*, malioc installed in /Applications/Arm Performance Studio 2026.5).
- Glass count: MorphGlassContainer (opt-in), package stages (search toolbar, list sections), tinted members join, raster phase/ties exact, scaled containers gated; MorphGlassInspector (debug counter with hints).
- UI thread: surfaces channel (no widget rebuild per tick), retained layers, parent-rebuild reuse, glyph atlas churn cut, menu rows prebuilt, menu fusion ahead on isolates (MorphFusionWorker).
- GPU/energy: small blurs bounded (edge effect copies its band; 2 pt frost raised to Impeller's half-res threshold on dpr 2.625): Pixel home-scroll 906 -> 565 mW, tab bar 1683 -> 905 mW.
- Rejected with evidence: ADPF (+9 % energy, branch exp/adpf), edge effects in the bars' group, nav bar + toolbar one container (+24 % GPU), frost inside the final shader, F1 uniforms, R1 shadow clip (no saveLayer existed).
- Harnesses: audit.sh / audit_android.sh (pinned worktree builds), energy_android.sh + energy.py (Pixel ODPM rails), gpu_work.py / gpu_scenes.py, perf_counts_test, glass_frames_test, menu_frames_test, launch_probe, g1455 one-binary bench (perf/2026-10-06-g1455-compare).

NEXT (in order):
1. Flat tier draws NO backdrop blur: MorphScrollEdgeEffect on flat = the fade/hairline only (owner 2026-10-06: "flat should have no blurs at all"). Measure Pixel GPU/energy; flat must equal Material-class GPU on scroll.
2. iOS verification of the 2026-10-06 work on the iPhone (Metal): small blurs, list stages, inspector, F7, fusion workers - audit.sh + shotdiff + shader parity (run_iphone.sh). The iPhone was with the owner.
3. Liquid controls UI thread: build p50 5.2 ms vs flat 1.95 on the Pixel - profile and cut (g1455-review idea 3).
4. GPU per scene was blind before g1455: run gpu_scenes.py on every audit scene (tab bar, sheet, menu) and look for more full-pass blurs / unbounded filters.
5. Owner decision pending: fusion workers 3 frames ahead (+4.5 - 6 % menu energy) vs 2.
6. Optional research: same-frame variant of g1455's capture (draw known content under clip+filter instead of a backdrop read; probe 1.36 vs 3.19 ms GPU, +0.6 ms raster naive).
Lessons: measure GPU and energy, not only frame timings (60 Hz hides GPU waste); never run on a device without its lock (mkdir must succeed); clean /tmp only after agents finish; on the Pixel keep portrait (auto-rotate broke runs).

## Order of work (owner's priorities)

1. Menu API leftovers (see above) - small, can ride with WP-E.
2. Audit fixes, in waves (packages have non-overlapping files; run at
   most 2-3 agents at once - usage limits cut every agent twice on
   2026-10-03):
   - Wave 1: WP-A engine routes/flights, WP-B engine registry/targets/
     skin (incl. FlutterError instead of assert + `!` and a `tryTagOf`;
     this is the sheet-zoom silent failure, still NOT fixed in release),
     WP-C bars/navigation, WP-I glass renderer, WP-J docs/hygiene.
   - Wave 2: WP-D sheets/zoom/alerts (needs WP-B), WP-E menus (largely
     folded into the menu API port - check what is left), WP-F lens
     family controls, WP-G other controls.
   - Wave 3: WP-H shared control host mixin, D5 merge of the two menu
     hosts (MorphMenuButton + the back-button menu in bar_items.dart).
   - Cross-package decisions: the lens travel spring is 0.401/0.856 in
     lens_motion.dart but 0.392/0.863 in two passports - check the
     recordings, fix the wrong side (WP-F + WP-J + keeper); the colour
     grouping rule for fused bar capsules (WP-C + WP-I).
3. Performance passport: re-measure everything on the iPhone 16 Pro
   (profile; example/integration_test/glass_audit_test.dart per tier,
   menu_trace_test, the release bench) and replace CLAUDE.md's stale
   2026-07-30 table. Then optimizations (fidelity first was the rule
   until here). Known costs: fused outline worst case 0.71 ms (4 pt
   blur), frosted tier reads the backdrop per surface (no BackdropGroup
   installed by the package - audit G-items), ~2000 lines of dead
   upstream renderer code compiled in.
4. Open fidelity items:
   - Light glass material of the renderer: resting glass button body
     251,251,252 vs native 245,245,251; menu interior 246,246,252 vs
     249,249,255. Fit on the PHONE against references/light/.
   - Reduce Motion pass: prepared (tool/ios_reference/reduce_motion.sh,
     ~25 min, RM_STEP= per family). Needs the OWNER to switch Settings >
     Accessibility > Motion > Reduce Motion on (agents must not change
     phone settings), and off again afterwards. Postponed by the owner.
   - Search keyboard's empty prediction bar: needs a Flutter engine
     change (spell checking is tied to autocorrect on iOS).
   - Smaller gaps listed per passport ("not reproduced").
5. Release 0.7.0: clean the history (stray commit 183fedf with a stale
   message), merge to main, tag, Pages, update the use-morph skill
   (tem_tools/plugins/morph; several versions behind).
6. dream_echo migration (other repo): it needs submenus + free-form menu
   rows (being built now), MorphTabBar / MorphGlassButton instead of
   CoopTug and Tug numbers; let its real usage order the remaining API
   gaps (spec/README.md status table lists them: tab bar minimize and
   bottom accessory, nav bar search placements, slider ranges, date
   picker styles, popovers, glass button sizes).

## How to run agents here (learned the hard way)

- Brief each agent with: read CLAUDE.md + its passport(s) + the audit IDs
  it owns; files it may touch; `git commit --only <paths>` (the tree is
  shared, never `git add -A`); do not push; ASCII only; no cascades, no
  `dynamic`, no explaining comments.
- Device rule (spec/README.md): widget tests on the Mac for logic and
  styles; the iOS 27 SIMULATOR (iPhone 18 Pro) for visual checks by
  screenshot; the iPhone 16 Pro only for 120 Hz timing, real touches,
  frame timings, final glass comparison and golden captures. Phone lock:
  `mkdir /tmp/morph-native/device.lock` + an `owner` file; release it.
- New measurements go through the reference keeper role (owns
  tool/ios_reference, fixtures, references, passports); porting agents
  read passports, not the probe.
- When the owner is gaming on the Mac: no GUI apps (no flutter run -d
  macos, no simulator windows, MorphRecorder only with `open -g`), tests
  with `nice -n 10 flutter test -j 2`.
- Usage-limit cut-offs leave uncommitted work in the tree; resume the
  same agent (SendMessage) instead of starting over, and ask agents to
  commit working increments early.
