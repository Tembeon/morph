List section stages on the Pixel 6a (Mali-G78, Vulkan, 60 Hz), 2026-10-06,
base 31eca1a plus the working tree of the change (worktrees, not committed
on their own). energy_android.sh, AUDIT_SCENES=home-scroll,list,
AUDIT_RUNS=5, liquid, shots on, every launch from a skin below 38 C, phone
on AC, battery full. Variants: nostage (HEAD's list.dart: no stage),
on (the stage, before the empty-layer renderer fix), off (on with
AUDIT_STAGES_OFF=true), on2 (the landed state). Launch order 1-3 nostage
on off, 4-9 off on nostage on nostage off, 10-15 on2 nostage nostage on2
on2 nostage. Traces (~34 MB each) are not kept; energy.py reprints from
the per-launch <run>.energy.json. Numbers in spec/glass-renderer.md
("List sections").
