// The glass container's merge law over up to FUSED_MAX_BOXES rounded boxes,
// the law the package samples into a field on the CPU
// (lib/src/liquid_field.dart LiquidField.eval and its flat sampler): the
// boxes fold in list order, each step blending the next box in over the
// angular width k sin^2 of half the angle between the carried and the
// next unit normal, k (1 - dot) / 2, and mixing the normals by the smooth
// minimum's own weight. A box that loses by k or more is skipped, one that
// wins by k or more replaces the fold, and a width under the narrowest
// that blends merges by the plain minimum.
//
// The includer defines FUSED_MAX_BOXES and declares, before the include,
// uniform vec4 uFusedBoxes[FUSED_MAX_BOXES * 2]: per box (center, half
// extents), then (corner radius, 0, 0, 0), the radius already clamped to
// the half extents. Shared by the liquid tier's analytic final pass
// (analytic_geometry.glsl) and the flat tier's fused bodies
// (lib/src/widgets/shaders/flat_fused_body.frag).

// The signed distance at p of the rounded box with center box.xy, half
// extents box.zw and corner radius r, and its unit normal: the normal of
// the corner circle outside the inner rectangle, else the dominant axis,
// mirrored into p's quadrant.
vec3 fusedBoxAt(vec2 p, vec4 box, float r) {
    vec2 local = p - box.xy;
    vec2 q = abs(local) - box.zw + r;
    vec2 outside = max(q, vec2(0.0));
    float len = length(outside);
    float d = len - r + min(max(q.x, q.y), 0.0);
    vec2 normal = len > 0.0
        ? outside / len
        : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    normal *= vec2(
        local.x < 0.0 ? -1.0 : 1.0,
        local.y < 0.0 ? -1.0 : 1.0
    );
    return vec3(d, normal);
}

// The angular fold at p of the first [count] boxes of uFusedBoxes, with
// spacing [k] and narrowest blending width [minWidth].
float fusedFold(vec2 p, int count, float k, float minWidth) {
    vec3 carried = fusedBoxAt(p, uFusedBoxes[0], uFusedBoxes[1].x);
    for (int i = 1; i < FUSED_MAX_BOXES; i++) {
        if (i >= count) break;
        vec3 next = fusedBoxAt(p, uFusedBoxes[i * 2], uFusedBoxes[i * 2 + 1].x);
        if (next.x - carried.x >= k) continue;
        if (carried.x - next.x >= k) {
            carried = next;
            continue;
        }
        float width = k * (1.0 - dot(carried.yz, next.yz)) * 0.5;
        if (width < minWidth) {
            if (next.x < carried.x) carried = next;
            continue;
        }
        float h = clamp(0.5 + 0.5 * (next.x - carried.x) / width, 0.0, 1.0);
        float d = next.x * (1.0 - h) + carried.x * h -
            width * h * (1.0 - h);
        vec2 n = next.yz * (1.0 - h) + carried.yz * h;
        float len = length(n);
        carried = vec3(d, len > 1e-12 ? n / len : vec2(0.0));
    }
    return carried.x;
}
