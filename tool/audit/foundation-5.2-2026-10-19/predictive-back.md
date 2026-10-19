# Predictive back on the Pixel 6a

2026-10-19, commit 4f83019f, example profile build, Android 17, gesture
navigation. The gallery's Navigation page is pushed, then a back gesture is
injected with `adb shell input motionevent` from the left edge (x 3 to 320
of 1080 at y 1300), with a screenshot while the finger is down.

`predictive-back-pixel.png`, left to right: cancel mid-gesture (the page
follows the gesture, the Widgets page shows under it), after the cancel
(the page is back), commit mid-gesture, after the commit (popped).

The first run, on a8255041, showed the system arrow but no preview: the
edge touch reached the page before the system claimed it for back, so the
page refused the gesture. 4f83019f cancels that touch and its edge swipe
and takes the gesture; `test/predictive_back_test.dart` covers it.
