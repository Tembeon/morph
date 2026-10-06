Menu scene of the glass audit frame by frame on the Pixel 6a (60 Hz),
example/integration_test/menu_frames_test.dart through audit_android.sh
(AUDIT_TARGET=integration_test/menu_frames_test.dart AUDIT_REPORT=menu_frames),
5 runs per launch, joined by perf/menu_frames.py (per-frame rows, per scene phase).

f2-base = d2c597c, f4-final = d2c597c + c4e4b43's menu changes (same source
tree otherwise). *-pre-fz = an instrumented build timing morphMenuSilhouette
per frame (a FlutterTimeline block, not committed); *-cpu = FRAMES_CPU Dart
samples. The raw JSON reports (2 MB each) are not committed; the .txt files
are menu_frames.py's output and fusion-and-cpu.txt the derived numbers.
