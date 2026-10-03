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
