# Native IME landing film results

2026-10-18, base `9256fc99`. iPhone 16 Pro, iOS 27.0.1, portrait 402x874 pt at 3x, fixed source `(161,406,80,48)`, ten menu rows. The public selection/reopen scenes from `native-ime-reopen` were filmed by the headless recorder under the device lock. Runs `landing-20261018-02` and `landing-20261018-03` each cover none/show/hide with two selections, which gives twelve close clips. Run `landing-20261018-01` stopped when the recorder failed to start (exit 1) and executed no test. No phone settings changed.

## Capture quality

Both receipts record generate, recorder-build, test, recorder, export and the three journal copies with exit 0. The film is a 60 Hz feed (median interval 16.667 ms) with zero capture and encode drops. Movie PTS are monotonic and the accepted buffer count equals the movie frame count. Each clip is anchored at the first frame whose on-screen selection counter shows the new value. That anchor is a visual event, not the callback time.

## Observations

The source comes to rest at the same pixels in every keyboard mode. All twelve final frames match the `none-1` frame of the same run within 4/255 at quarter scale, with no pixel over 24/255. This holds for show, where the keyboard stays visible, and for hide, where the menu opened above a keyboard that later disappeared.

Rest arrives 0.38 to 0.43 s after the anchor in all twelve clips. Rest means every later frame in the 2.2 s window stays within mean 0.5/255 of the window's last frame.

The closing trajectory is measured in only four clips. The pre-registered rule rejects a clip whose window from -0.1 to +1.2 s contains a gap over 50 ms. Run 02 none-1, show-1, show-2 and hide-1 pass with gaps of 33 to 50 ms. The other eight clips have gaps of 58 to 92 ms and stay inconclusive.

Three clips contain one blank frame. In run 02 hide-1, run 03 none-1 and run 03 show-2 the anchor frame shows no menu in the source crop, only a small unlabeled glass ellipse at the source. Its mean crop level is 2.06/255 against 20 to 29 for both neighbours. The next frame shows the menu again and the normal close follows. The cause is unknown. It may be a real one-frame display state or an artifact of the capture path. It is not a behaviour to port. The blank-frame rule and the 0.5/255 rest tolerance are descriptive and were chosen after viewing the boards. The 50 ms gap rule and the windows were fixed before analysis.

## Limits

The source never moves, so opening-time and current source geometry coincide. These films cannot tell which one the close targets. A private reading of UIKit suggests the dismissal keeps the opening-time container and center while sampling the source's current transform. That reading is unverified at runtime and needs a moved-source control.

The anchor is a counter frame, so rest times carry one capture frame of uncertainty and no device-clock fit. Static rest does not prove the whole trajectory.

## Consequence for P2

Nothing here changes the Flutter landing policy. Under a fixed source the native close returns to the same place regardless of keyboard state, which the current prototype already does. The conservative detach on a changed placement stays until a moved-source control decides whether the source may accept the model after its geometry changed.

## Evidence

- `landing-20261018-0{2,3}/commands.json` hold the command receipts and source hashes.
- `landing-20261018-0{2,3}/film-analysis.json` holds capture metadata, counter spans, gaps and board frame times.
- `landing-20261018-0{2,3}/rest-analysis.json` holds rest times, final-frame comparisons and blank-frame detections.
- `landing-20261018-02/film-show-1-board.png` shows an accepted clip. `film-hide-1-board.png` shows the blank anchor frame.
- The raw whole-device movies, buffer metadata and both analysis scripts stay private under `~/morph-re/measurements/menu-keyboard/` and `~/morph-re/tools/`.
