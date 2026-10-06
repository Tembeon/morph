Segmented scene on the Pixel 6a: where the liquid tier's raster goes once
the filters are off (glass_audit_test.dart, AUDIT_SCENES=segmented,
AUDIT_RUNS=2, one systrace launch each, TraceSystrace meta-data and a local
ABL define in a worktree at ec62123, never committed). Builds: flat; a0 =
navigation bar on the flat tier + no lifted lens glass layer; a1 = a0 + no
lens content copy; a2 = a1 + no content capture; a3 = a2 + no content clip;
a4 = a3 + no platter; a5 = navigation bar and segmented controls flat; a6 =
a5 + no lens glass; liquid. trace-final-trace-{base,final} are segmented +
controls at ec62123 and with the frost seed + platter fade (this batch).
trace-slices.txt: raster-thread slices per raster frame (count, self ms,
inclusive ms), the frames split by (saveLayers, queue submits), and the
saveLayer self-time distribution per frame.
