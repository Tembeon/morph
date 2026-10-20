// The tints of a fused body (a GlassBoxField) for its tint-only matte
// variants (FUSED_TINT): the analytic fused variants' law (fused_law.glsl
// fusedBoxTint), so a resting frame draws the seam where two shapes'
// tints meet exactly where the moving frames draw it, with no material
// map.
//
// Included by liquid_glass_final_render_core.glsl after its uniforms, so
// these follow its float uniforms (from float index 81), where the
// analytic variants declare theirs.

#define FUSED_MAX_BOXES 4

// Per box, in matte device pixels: (center, half extents), then (corner
// radius clamped to the half extents, 0, 0, 0).
uniform vec4 uFusedBoxes[FUSED_MAX_BOXES * 2];
// Each box's tint, unpremultiplied, as the material map holds it.
uniform vec4 uFusedTints[FUSED_MAX_BOXES];
// The fused boxes.
uniform float uFusedTintBoxes;

#define FUSED_TINTS uFusedTints
#include "fused_law.glsl"
