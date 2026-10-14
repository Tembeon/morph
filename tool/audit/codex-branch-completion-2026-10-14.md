# Interrupted Claude branches: completion, 2026-10-14

Scope: finish the four agents interrupted by the session limit, integrate them
into `wip/measured-liquid-glass`, and continue the physical iPhone checks.
No release to `main`, tag or push is part of this work.

## Preserved and integrated work

- Context menus: `worktree-agent-a287832b3ca02ff82`, through `51616142`.
  Shared menu controller, rows, blob morph, composite preview, custom preview
  and accessory; eight commits preserved by merge.
- Search and tab bars: `worktree-agent-a958794b6d28dc670`, through `00904f22`.
  Stacked search, manual search tab role, minimize rules and controlled search;
  six commits preserved by merge.
- Navigation bars: `worktree-agent-a41eb6f5957868ba8`, through `fdcc6da4`.
  Title bounds, hiding, vertical scroll indicator. Five uncommitted gallery
  and count changes preserved in `93618e83` before merging.
- Navigation transitions: `worktree-agent-af36cf383ec30c339`, through `107aebd3`.
  Continuous card corners, under-page dim, content back swipe and gesture
  arbitration; three commits preserved by merge.
- Sheets were already merged into `338ae8a2`; the stopped `sheets-device`
  session had prepared a 68-line capture test but had not run it. The
  previously uncommitted test is also preserved and integrated.

Search/scaffold conflicts were resolved by retaining both stacked search's
presentation and toolbar search's animated bar hiding. Neither moves the
content twice. Documentation and migration entries from both branches remain.

## Checks and remaining work (in progress)

Initial combined analysis found no production-code issues. Four independent
full suites had overloaded the host; two orphaned testers were still alive.
They were terminated. A single combined `flutter test -j 2` run is used to
separate actual regressions from overloaded software screenshot rendering.
Raw logs: `/tmp/morph-codex-root-tests.log`, `/tmp/morph-codex-analyze.log`.

Initial confirmed failures: nav-scroll rebuild counts and navigation lifecycle
ceilings, including values that independently changed branches could not
combine arithmetically. Glyph image tests retain their original pixel thresholds.

Follow-up changes under verification:
- Live hit testing for the hiding bar instead of a rebuilding value builder.
- Controlled toolbar hiding updates deferred out of ancestor builds.
- Stacked search shares its query controller at rest and mirrors its close
  button and field layout in right-to-left text.
- Phone capture scenarios cover the pending sheet plan and held tab badges.

Device observations, final check results and commits are appended when verified.
