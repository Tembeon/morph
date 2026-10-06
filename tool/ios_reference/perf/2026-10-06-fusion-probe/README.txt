example/integration_test/fusion_probe.dart (profile builds) over the
gallery's recorded menu fusions (support/fusion_inputs.dart), the
FUSION lines of each launch. hash = the package's fusion against the
frozen pre-change one (support/fusion_baseline.dart; 105/108 and 212/218
equal after the kernel-reach fix, before it 108/108 and 218/218); tight =
back to back; core N = the UI thread pinned to CPU N (Pixel 6a: 0-3 A55,
4-5 A76, 6-7 X1); paced = one fusion a frame in an idle app, with the
CPU it ran on and its thread CPU time; -evicted = 16 MB touched first;
-spun = 4 ms busy first; worker = the next fusion fused ahead on the
fusion worker and served (hits), the UI cost of a served and of a
missed frame; cpu = Dart CPU samples of the tight pass by function.
macos-base / iphone-base: before the worker (the paced and tight
columns are the gap's evidence); iphone-worker: the first worker;
iphone-final, pixel6a-probe: the committed state.
