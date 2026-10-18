# Public optical IME close observation

- [x] Consult private lab; retain all raw RE/derivation material outside git.
- [x] Record existing public UIKit selection/reopen scenes none/show/hide on iPhone through a headless recorder process under the same atomic device lock.
- [x] Validate real successful scenes, recorder exit/source hashes and video timestamps/drop metadata; identify action windows visually using our selection counter.
- [x] Inspect source region across closure and after rest; repeat any admitted observation. Preserve gaps/unknowns.
- [x] Update bounded behavior documentation and verify tools, deslop/no-comments, scoped local commit.

Native app/tests and source geometry remain unchanged for the first observation. Source `(161,406,80,48)` stays fixed while keyboard changes. That experiment can show sampled optical return after IME; it cannot distinguish old/current source targets because they coincide. A separate moved-source control would be needed for that rule.

Movie timing is its presentation timestamp domain, not automatically the device's CACurrentMediaTime. Use visible selection counter/our own scene to identify transitions; no cross-clock fit or warped video. Record actual cadence and coverage; do not claim120Hz observation from a60Hz screen feed or continuous optical truth across gaps. No fidelity threshold may be changed after observing output.

Acceptance for a bounded film observation: successful test+export/copy; recorder0; three scene counter sequences0→1→2 identifiable; source return/rest visible in unclipped source ROI; monotonic frame PTS and report actual maximum gaps around each close. A gap over50ms in a close window leaves its trajectory inconclusive, even if endpoint/rest is visible. Transient coverage window is fixed before image analysis: counter transition−0.1s through+1.2s; inspect source/rest through+2.2s. Static rest never proves the full trajectory. No Flutter landing policy changes follow from fixed-source imagery alone.

Use existing AVFoundation recorder as a headless console executable without open/macOS windows or simulator. Only our own process is stopped; raw whole-device movies/logs remain private and repository output excludes app launch/Springboard/other apps. No phone settings change, no concurrent device/heavy jobs, no main/push.
